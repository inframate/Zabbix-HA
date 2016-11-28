#!/bin/sh

CONFIG="mariadb.domain.com"
VM=`cat /etc/hostname`


mysql -uroot -pdevops -e 'STOP SLAVE;'
MASTERLOGFILE=$(grep mariadb /CONFIGs/$CONFIG/master-slave_status | awk '{print $1}')
MASTERLOGPOS=$(grep mariadb /CONFIGs/$CONFIG/master-slave_status | awk '{print $2}')
mysql -uroot -pdevops -e "CHANGE MASTER TO MASTER_HOST='mariadb-master1.domain.com', MASTER_USER='zabbix', MASTER_PASSWORD='zabbix', MASTER_LOG_FILE='$MASTERLOGFILE', MASTER_LOG_POS=$MASTERLOGPOS"
mysql -uroot -pdevops -e 'SLAVE START;'
sleep 2 && mysql -uroot -pdevops -e 'SHOW SLAVE STATUS\G;' | grep "Running"

rm -f /CONFIGs/$CONFIG/master-slave_status

printf "\n>>>\n>>> Finished provisionning $VM\n>>>\n\n>>> MariaDB is reachable via:\n>>> USERNAME: root\n>>> PASSWORD: devops\n"
