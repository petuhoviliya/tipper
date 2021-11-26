#!/bin/bash

# Настройки выполнения скрипта
#set -euo pipefail

# It's a kind of magic
export DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $DIR

if [ -f ./config.sh ]
then
    source ./config.sh
else
    echo "Main config \"config.sh\" not found, terminate"
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
            
                clean_backup
            else
                log_message "There is no config files in \"$CONFIG_DIR\", terminate"
            fi
        done

        if [ "$BK_REMOTEBACKUP" = true ]
        then
	        remote_replication
        fi
    else
        log_message "Dir \"$CONFIG_DIR\" is missing, terminate"
        exit 1
    fi

    log_message "End of backup session"
    
    REPORT_SMS_TXT="${REPORT_SMS_TXT} \n\n $(df -h $BK_PATHTOBACKUP)\n"
    
    make_report
}


work_on_config(){
      
    # очишаем значения переменных, импортированных из скрипта конфигурации хоста, пере обработкой следующего
    clean_environment
    
    source "$1"
    date=$(date "+%Y-%m-%dT%H:%M:%S")
    
    log_message "Start processing host: $BK_HOSTNAME"
      
    if [ "$DO_DEBUG" = true ]
    then
        log_message "Hostname: $BK_HOSTNAME"
        log_message "Host ip: $BK_HOSTIP"
        log_message "SSH user: $BK_SSHUSER"
        log_message "Method: $BK_METHOD"
        log_message "Method options: $BK_METHOD_OPTIONS"
        log_message "Pre exec: $BK_PRE_EXEC"
        log_message "Post exec: $BK_POST_EXEC"
        log_message "Filesystem source: $BK_FSSOURCE"
        log_message "DB type: $BK_DBTYPE"
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
    create_db_backup
    create_fs_backup
    
}


check_settings(){
    #TODO:
    # добавить проверку локального наличиния бинарников ssh, rsync, gzip и прочего, что используеться в скрипте
    # и добавить аналогичную проверку для удаленного хоста
    # which mailxx > /dev/null 2>&1; echo $?

    log_message "Check backup settings"
    
    if [ ! -d "$BK_PATHTOBACKUP/$BK_HOSTNAME" ]
    then
        log_message "Backup directory for $BK_HOSTNAME not found, creating..."
        mkdir "$BK_PATHTOBACKUP/$BK_HOSTNAME"
    fi

    log_message "Check bin available"    

    check_bin_available

}

check_bin_available(){
# Локальные бинайнрки
# ssh
# rsync
# gzip
# mailx
# 
    check_failed=0
    for j in ssh rsync gzip mailx 
    do
        if [ `which $j > /dev/null 2>&1;echo $?` -gt 0 ];
        then
            log_message "Binary \"$j\" not found"
            check_failed=1
        else
            if [ "$DO_DEBUG" = true ]
            then
                log_message "Binary \"$j\" - OK"
            fi
        fi
        
    done
    return $check_failed
}

create_fs_backup(){

    if [ "$BK_FSSOURCE" = none ];
    then
        log_message "FS backup not needed"
        REPORT_SMS_TXT="${REPORT_SMS_TXT} none\n"
        return 0
    fi

    log_message "Start FS backup"
  
    fs_dirs=$(echo "$BK_FSSOURCE"  | tr ";" "\n")

    EXCLUDE_PATTERN=""
    if [[ ! -z "$BK_FSSOURCE_EXCLUDE" ]]
    then
        log_message "Exclude patterns: ${BK_FSSOURCE_EXCLUDE}"
        #EXCLUDE_PATTERN="--exclude '${BK_FSSOURCE_EXCLUDE}'"
        EXCL_DIRS=$(echo "$BK_FSSOURCE_EXCLUDE"  | tr ";" "\n")

        for EXCL_DIR in $EXCL_DIRS
        do

            EXCLUDE_PATTERN="${EXCLUDE_PATTERN} --exclude='${EXCL_DIR}'"

        done
    fi
 
    if [[ ! -z "$BK_METHOD" ]]
    then 
        METHOD="${BK_METHOD}"
    else
        METHOD="rsync"
    fi
    log_message "Using method: ${METHOD}" 

    if [[ ! -z "$BK_PRE_EXEC" ]]
    then
        ssh $BK_SSHUSER@$BK_HOSTIP "${BK_PRE_EXEC}"
        sleep 10
        log_message "Execute pre-exec command: ${BK_PRE_EXEC} --- $?"
    fi
    
    for fs_dir in $fs_dirs
    do
        case $METHOD in
            scp)
                scp -q -r -p $BK_METHOD_OPTIONS $BK_SSHUSER@$BK_HOSTIP:$fs_dir $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---FS 2>> $LOGS_DIR/scp-$date.log
                log_message "Working on $fs_dir --  $?"
                ;;

            rsync)
                rsync -azhR --chmod=ug=rwX,o= $BK_METHOD_OPTIONS --link-dest=$BK_PATHTOBACKUP/$BK_HOSTNAME/CURRENT---FS $EXCLUDE_PATTERN $BK_SSHUSER@$BK_HOSTIP:$fs_dir $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---FS 2>> $LOGS_DIR/rsync-$date.log
                log_message "Working on $fs_dir --  $?"
                ;;
        esac
    done
  
    ln -n -f -s $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---FS $BK_PATHTOBACKUP/$BK_HOSTNAME/CURRENT---FS
    
    log_message "--FS size: $(du -h -d 0 $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---FS)"
    
    if [[ ! -z "$BK_POST_EXEC" ]]
    then
        ssh $BK_SSHUSER@$BK_HOSTIP "${BK_POST_EXEC}"
        sleep 10
        log_message "Execute post-exec command: ${BK_POST_EXEC} --- $?"
    fi
    
    REPORT_SMS_TXT="${REPORT_SMS_TXT} $(du -h -d 0 $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---FS | awk '{print $1}')\n"
}


create_db_backup(){

    if [ "$BK_DBHOST" = none ];
    then
        log_message "DB backup not needed"
        REPORT_SMS_TXT="${REPORT_SMS_TXT} none"
        return 0
    fi

    if [[ ! -z "$BK_DBTYPE" ]]
    then 
        DBTYPE="${BK_DBTYPE}"
    else
        DBTYPE="mysql"
    fi

    log_message "Start DB backup"
    
    # TODO:
    # сделать проверку на наличие указанного бинарника в удаленной системе
    case $DBTYPE in
        mysql)  
            db_dump_exec=$(ssh $BK_SSHUSER@$BK_HOSTIP which mysqldump)
            db_dump_options="$BK_DBOPTIONS -u $BK_DBUSER -p$BK_DBPASS $BK_DBNAME"
            ;;
        mongo) 
            db_dump_exec=$(ssh $BK_SSHUSER@$BK_HOSTIP which mongodump)
            db_dump_options="-d $BK_DBNAME $BK_DBOPTIONS"
            ;;
        postgresql) 
            db_dump_exec=$(ssh $BK_SSHUSER@$BK_HOSTIP which pg_dump)
            db_dump_options="$BK_DBOPTIONS --username=$BK_DBUSER --dbname=$BK_DBNAME"
            # pg_dump --if-exists --clean --create -U backup -d dvtender
            ;;
        *)
            log_message "WTF?! Unknown DB type: \"$DBTYPE\", terminate"
            return 1
            ;;
    esac
  
    log_message "DB type: $DBTYPE"
   
    if [[ -z "$db_dump_exec" ]];
    then
        log_message "ERROR! DB dump binary for \"$DBTYPE\" does not exist, terminate"
        return 1
    fi

    # TODO:
    # здесь надо поправить BK_DBHOST, потому что если база находиться на другом физическом хосте и хоть и относиться
    # к этому же серверу, но пользователь для ssh там может быть, точнее скорее всего, другой
    # так же поправить логику дампа БД и описание шаблона конфига 
    # ssh user@host mysqldump -h dbhost -u dbuser -p dbpass

    if [ "$COMPRESS_DB" = true ];
    then
        
        log_message "Backuping to gzip-ed file"
        
        #ssh $BK_SSHUSER@$BK_HOSTIP mysqldump $BK_DBOPTIONS -u $BK_DBUSER -p$BK_DBPASS $BK_DBNAME | $COMPRESS_BIN $COMPRESS_OPT  > $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB.gz
        #echo "ssh $BK_SSHUSER@$BK_HOSTIP $db_dump_exec $db_dump_options | $COMPRESS_BIN $COMPRESS_OPT > $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB.gz"
        ssh $BK_SSHUSER@$BK_HOSTIP $db_dump_exec $db_dump_options | $COMPRESS_BIN $COMPRESS_OPT > $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB.gz

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
            
            ssh $BK_SSHUSER@$BK_HOSTIP $db_dump_exec $db_dump_options > $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB
            log_message "--Done with code: $?"
        fi
    else
        #ssh $BK_SSHUSER@$BK_HOSTIP mysqldump $BK_DBOPTIONS -u $BK_DBUSER -p$BK_DBPASS $BK_DBNAME > $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB
        ssh $BK_SSHUSER@$BK_HOSTIP $db_dump_exec $db_dump_options > $BK_PATHTOBACKUP/$BK_HOSTNAME/$date---DB
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
    nohup /bin/bash $DIR/clean_backup.sh $BK_PATHTOBACKUP/$BK_HOSTNAME/ $BK_KEEPDAYS > $LOGS_DIR/clean-$date.log 2>/dev/null &
}


log_message(){

    echo -e "$(date "+%Y-%m-%d %H:%M:%S") : $1"
    echo -e "$(date "+%Y-%m-%d %H:%M:%S") : $1">> $REPORTS_DIR/$REPORT_FILE
}


make_report(){

    log_message  "Sending report"    
    echo -e "Backup report attached to this message\n$REPORT_SMS_TXT\n\n----------------\n$REPORT_EMAIL_FROM" | mailx -a $REPORTS_DIR/$REPORT_FILE -s "Backup report `hostname`" -r $REPORT_EMAIL_FROM $REPORT_EMAIL_TO
}

clean_environment(){
    log_message "Clean environment"
    export BK_HOSTNAME=''
    export BK_HOSTIP=''
    export BK_SSHUSER=''
    export BK_METHOD=''
    export BK_METHOD_OPTIONS=''
    export BK_PRE_EXEC=''
    export BK_POST_EXEC=''
    export BK_FSSOURCE=''
    export BK_DBTYPE=''
    export BK_DBHOST=''
    export BK_DBUSER=''
    export BK_DBOPTIONS=''
    export BK_DBNAME=''
    export BK_DBMINSIZE=''
    export BK_KEEPDAYS=''   
}


if [ $# == 1 ]
then
    work_on_config "$1"
else
    main
fi

