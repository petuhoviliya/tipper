#!/bin/bash

# $1 - каталог где искать бэкапы
# $2 - $BK_KEEPDAYS 
# $3 - $date

if [ -d $1 ]
then
	find $1 -maxdepth 1 -type d -name "*FS*" -ctime +$2 -exec rm -Rf {} +
	find $1 -maxdepth 1 -type f -name "*DB*" -ctime +$2 -exec rm -Rf {} +
fi
