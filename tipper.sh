#!/bin/bash

# metadata
NAME='tipper'
VERSION='v1.0'
AUTHOR='Nikita CryptoManiac Sivakov <cryptomaniac.512@gmail.com>'

HOSTNAME=''
HOSTIP=''
SSHUSER=''
FSSOURCE=''
DBUSER=''
DBPASS=''
DBNAME=''
PATHTOBACKUP='/home/backup_daemon/data'
date=`date "+%Y-%m-%dT%H:%M:%S"`


# Full logic in functions
check_backup_dir () {
    if [ -d $PATHTOBACKUP/$HOSTNAME ]
    then
        log_message "Backup directory for $HOSTNAME exists. All is well."
    else
        log_message "Backup directory for $HOSTNAME not found. Creating..."
        mkdir $PATHTOBACKUP/$HOSTNAME
    fi
}

create_fs_inc_backup () {
    rsync -azh --stats --link-dest=$PATHTOBACKUP/$HOSTNAME/CURRENT---FS $SSHUSER@$HOSTIP:$FSSOURCE $PATHTOBACKUP/$HOSTNAME/$date---FS
    rm $PATHTOBACKUP/$HOSTNAME/CURRENT---FS
    ln -s $PATHTOBACKUP/$HOSTNAME/$date---FS $PATHTOBACKUP/$HOSTNAME/CURRENT---FS
    echo -e "\n`du -h -d 0 $PATHTOBACKUP/$HOSTNAME/$date---FS`\n"
}

create_mysql_backup () {
    ssh $SSHUSER@$HOSTIP mysqldump -u $DBUSER -p$DBPASS $DBNAME > $PATHTOBACKUP/$HOSTNAME/$date---DB
    echo -e "\n`du -h $PATHTOBACKUP/$HOSTNAME/$date---DB`\n"
}


check_backup_quantity () {
    find $PATHTOBACKUP/$HOSTNAME/ -type d -name "*FS*" -ctime +13 -exec rm -Rf {} +
    find $PATHTOBACKUP/$HOSTNAME/ -type d -name "*DB*" -ctime +13 -exec rm -Rf {} +
}

run_and_say () {
    log_message "Start $2"
    if $1; then
        log_message "Complete $2 for $HOSTNAME"
    else
        log_message "Failed $2 for $HOSTNAME"
    fi
}

log_message () {
    echo -e "$NAME $VERSION : `date "+%Y-%m-%d %H:%M:%S"` : $1"
}

# Function-runner
main () {
    log_message "Start $HOSTNAME processing"
    check_backup_dir
    run_and_say create_fs_inc_backup 'filesystem sync'
    run_and_say create_mysql_backup 'database backup processing'
    check_backup_quantity
    log_message "End of $HOSTNAME processing\n\n"
}


# Run programm
main
