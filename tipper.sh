#!/bin/bash

# Simple and powerful backup script 
# Original script author: Nikita CryptoManiac Sivakov <cryptomaniac.512@gmail.com>
# https://github.com/sivakov512/tipper
# 
# New functionality and some improvements: Ilya Petukhov https://github.com/petuhoviliya/tipper
#

# It's a kind of magic
export DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

if [ -f ./config.sh ]
then
    source ./config.sh
else
    echo "Main config \"config.sh\" not found, aborting"
    exit 1
fi

#main function
main(){

    log_message "Start backup session"
    log_message "Working dir: $( pwd )"
 
    if [ ! -d "$BK_PATHTOBACKUP" ]
    then
        mkdir -p "$BK_PATHTOBACKUP"

    fi 

    if [ ! -d "$REPORTS_DIR" ]
    then
        mkdir -p "$REPORTS_DIR"
    fi 

    if [ ! -d "$LOGS_DIR" ]
    then
        mkdir -p "$LOGS_DIR"
    fi 

    if [ -d "$CONFIG_DIR" ]
    then
        for HOST_CONFIG in $CONFIG_DIR/*.sh
        do

            if [ -f "$HOST_CONFIG" ]
            then    
                log_message "----------------------------"
                log_message "Start $HOST_CONFIG processing"
        
                work_on_config "$HOST_CONFIG"
                
                if [ "$BK_REMOTEBACKUP" = true ]
            	then
	                remote_replication
            	fi

                clean_backup
            else
                log_message "There is no config files in \"$CONFIG_DIR\", aborting"
            fi

        done
    else
        log_message "Dir \"$CONFIG_DIR\" is missing, aborting"
        exit 1
    fi

    log_message "End of backup session"
    
    make_report
}


work_on_config(){
      
    source "$1"
    date=$(date "+%Y-%m-%dT%H:%M:%S")
    
    log_message "Start processing host: $BK_HOSTNAME"
      
    if [ "$DO_DEBUG" = true ]
    then
        log_message "Hostname: $BK_HOSTNAME"
        log_message "Host ip: $BK_HOSTIP"
        log_message "SSH user: $BK_SSHUSER"
        log_message "Filesystem source: $BK_FSSOURCE"
        log_message "DB host: $BK_DBHOST"
        log_message "DB user: $BK_DBUSER"
        log_message "DB options: $BK_DBOPTIONS"
        log_message "DB name: $BK_DBNAME"
        log_message "DB mininum size: $BK_DBMINSIZE"
        log_message "Path to backup: $BK_PATHTOBACKUP"
        #log_message "Configs to backup: $BK_CONFS"
        #log_message "Path where config backup to: $BK_PATHTOCFGBACKUP"
        log_message "Keep backup days: $BK_KEEPDAYS"
    fi

    REPORT_SMS_TXT="${REPORT_SMS_TXT}${BK_HOSTNAME}:"
      
    check_settings
    create_mysql_backup
    create_fs_backup
}


check_settings(){
    
    log_message "Check backup settings"
    
    if [ ! -d "$BK_PATHTOBACKUP/$BK_HOSTNAME" ]
    then
        log_message "Backup directory for $BK_HOSTNAME not found, creating..."
        mkdir "$BK_PATHTOBACKUP/$BK_HOSTNAME"
    fi
}


create_fs_backup(){

    log_message "Start FS backup"
  
    fs_dirs=$(echo "$BK_FSSOURCE"  | tr ";" "\n")

    if [[ ! -z "$BK_FSSOURCE_EXCLUDE" ]]
    then
        EXCLUDE_PATTERN="--exclude={${BK_FSSOURCE_EXCLUDE}}"
    else
        EXCLUDE_PATTERN=''
    fi
  
    log_message "Exclude patterns: ${EXCLUDE_PATTERN}"
  
    for fs_dir in $fs_dirs
    do
        rsync -azhR --link-dest=$BK_PATHTOBACKUP/$BK_HOSTNAME/CURRENT---FS $BK_SSHUSER@$BK_HOSTIP:$fs_dir $EXCLUDE_PATTERN $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---FS 2>> $LOGS_DIR/rsync-$date.log
        log_message "Working on $fs_dir --  $?"
    done
  
    rm $BK_PATHTOBACKUP/$BK_HOSTNAME/CURRENT---FS
    ln -s $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---FS $BK_PATHTOBACKUP/$BK_HOSTNAME/CURRENT---FS
    
    log_message "--FS size: $(du -h -d 0 $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---FS)"
    
    REPORT_SMS_TXT="${REPORT_SMS_TXT} $(du -h -d 0 $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---FS | awk '{print $1}')\n"
}


create_mysql_backup(){

    if [ "$BK_DBHOST" = none ];
    then
        log_message "DB backup not needed"
        REPORT_SMS_TXT="${REPORT_SMS_TXT} none"
        return 0
    fi

    log_message "Start DB backup"
    
    if [ "$COMPRESS_DB" = true ];
    then
        
        log_message "Backuping to gzip-ed file"
        
        ssh $BK_SSHUSER@$BK_DBHOST mysqldump $BK_DBOPTIONS -u $BK_DBUSER -p$BK_DBPASS $BK_DBNAME | $COMPRESS_BIN $COMPRESS_OPT  > $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB.gz
        INTEGRITY_CHECK=$($COMPRESS_BIN -t $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB.gz 2>&1)
        
        if (($? == 0))
        then
            log_message "--Integrity check: OK"
        else
            INTEGRITY_CHECK=$(echo "$INTEGRITY_CHECK" | tr '\n' ' ')
      
            log_message "--Integrity check: Failed"
            log_message "--Message: ${INTEGRITY_CHECK}"
            log_message "--Deleting corrupted file"
      
            rm -f $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB.gz
            
            log_message "--Done with code: $?"
            
            log_message "Starting fallback backup"
            
            ssh $BK_SSHUSER@$BK_DBHOST mysqldump $BK_DBOPTIONS -u $BK_DBUSER -p$BK_DBPASS $BK_DBNAME > $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB
            log_message "--Done with code: $?"
        fi
    else
        ssh $BK_SSHUSER@$BK_DBHOST mysqldump $BK_DBOPTIONS -u $BK_DBUSER -p$BK_DBPASS $BK_DBNAME > $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB
        log_message "--Done with code: $?"
    fi
  
  log_message "--DB size: `du -h $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB*`"
  REPORT_SMS_TXT="${REPORT_SMS_TXT} $(du -h $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB* | awk '{print $1}')"
}


remote_replication(){
  
    log_message "Start backup replication to \"$BK_REMOTEBACKUPPATH\""
    $BK_REMOTEBACKUPCMD $BK_PATHTOBACKUP/ $BK_REMOTEBACKUPPATH/ > $LOGS_DIR/replica-$date.log 2>/dev/null
    total_sent=$(grep -Eo 'sent [0-9.GgKkMm]*' $LOGS_DIR/replica-$date.log | awk '{print $2}')
    total_size=$(grep -Eo 'total size is [0-9.GgKkMm]*' $LOGS_DIR/replica-$date.log | awk '{print $4}')
    log_message "-- Total sent: $total_sent, total size: $total_size"
}


clean_backup(){

    log_message "Start background old backup clean"
    nohup /bin/bash clean_backup.sh $BK_PATHTOBACKUP/$BK_HOSTNAME/ $BK_KEEPDAYS > $LOGS_DIR/clean-$date.log 2>/dev/null &
}


log_message(){

    echo -e "$(date "+%Y-%m-%d %H:%M:%S") : $1"
    echo -e "$(date "+%Y-%m-%d %H:%M:%S") : $1">> $REPORTS_DIR/$REPORT_FILE
}


make_report(){

    log_message  "Sending report"    
    echo -e "Backup report attached to this message\n$REPORT_SMS_TXT\n\n----------------\n$REPORT_EMAIL_FROM" | mailx -a $REPORTS_DIR/$REPORT_FILE -s "Backup report" -r $REPORT_EMAIL_FROM $REPORT_EMAIL_TO
}


if [ $# == 1 ]
then
    work_on_config "$1"
else
    main
fi

