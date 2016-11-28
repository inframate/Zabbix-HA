#!/bin/sh

CONFIG="mariadb.domain.com"
VM=`cat /etc/hostname`

printf "\n>>>\n>>> WORKING ON: $VM ...\n>>>\n\n>>>\n>>> (STEP 1/6) Configuring system ...\n>>>\n\n\n"
sleep 5
sed -ri 's/127\.0\.0\.1\s.*/127.0.0.1 localhost localhost.localdomain/' /etc/hosts
echo 'root:devops' | chpasswd
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && service sshd restart
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
echo 0 > /sys/fs/selinux/enforce



printf "\n>>>\n>>> (STEP 2/6) Installing MariaDB ...\n>>>\n\n"
sleep 5
yum install -y mariadb-server mariadb
cp /CONFIGs/$CONFIG/master1.cnf /etc/my.cnf.d/
systemctl start mariadb && systemctl enable mariadb
mysql_secure_installation <<EOF

y
devops
devops
y
y
y
y
EOF

printf "\n>>>\n>>> (STEP 3/6) Configuring MariaDB Master1...\n>>>\n\n"
sleep 5
mysql -uroot -pdevops -e 'CREATE DATABASE zabbix;' \
-e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'%' IDENTIFIED BY 'zabbix';" \
-e 'FLUSH PRIVILEGES;'
mysql -uroot -pdevops zabbix < /CONFIGs/$CONFIG/create.sql

mysql -uroot -pdevops -e 'STOP SLAVE;' \
-e "GRANT REPLICATION SLAVE ON *.* TO 'zabbix'@'%' IDENTIFIED BY 'zabbix';" \
-e 'FLUSH PRIVILEGES;' \
-e 'FLUSH TABLES WITH READ LOCK;'
mysql -uroot -pdevops -e 'SHOW MASTER STATUS\g' > /CONFIGs/$CONFIG/master1_status

mysql -uroot -pdevops -e 'STOP SLAVE;'
MASTERLOGFILE=$(grep mariadb /CONFIGs/$CONFIG/master2_status | awk '{print $1}')
MASTERLOGPOS=$(grep mariadb /CONFIGs/$CONFIG/master2_status | awk '{print $2}')
mysql -uroot -pdevops -e "CHANGE MASTER TO MASTER_HOST='mariadb-master2.domain.com', MASTER_USER='zabbix', MASTER_PASSWORD='zabbix', MASTER_LOG_FILE='$MASTERLOGFILE', MASTER_LOG_POS=$MASTERLOGPOS"
mysql -uroot -pdevops -e 'SLAVE START;'
sleep 2 && mysql -uroot -pdevops -e 'SHOW SLAVE STATUS\G;' | grep "Running"
#give root remote access from other cluster members
mysql -uroot -pdevops -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'mariadb-master2.domain.com' IDENTIFIED BY 'devops' WITH GRANT OPTION;"



printf "\n>>>\n>>> (STEP 4/6) Configuring MariaDB Master2 Remotely from Master1...\n>>>\n\n"
sleep 5
mysql -h mariadb-master2.domain.com -uroot -pdevops -e 'STOP SLAVE;'
MASTERLOGFILE=$(grep mariadb /CONFIGs/$CONFIG/master1_status | awk '{print $1}')
MASTERLOGPOS=$(grep mariadb /CONFIGs/$CONFIG/master1_status | awk '{print $2}')
mysql -h mariadb-master2.domain.com -uroot -pdevops -e "CHANGE MASTER TO MASTER_HOST='mariadb-master1.domain.com', MASTER_USER='zabbix', MASTER_PASSWORD='zabbix', MASTER_LOG_FILE='$MASTERLOGFILE', MASTER_LOG_POS=$MASTERLOGPOS"
mysql -h mariadb-master2.domain.com -uroot -pdevops -e 'SLAVE START;'
sleep 2 && mysql -h mariadb-master2.domain.com -uroot -pdevops -e 'SHOW SLAVE STATUS\G;' | grep "Running"

printf "\n>>>\n>>> (STEP 5/6) Installing Pacemaker & Corosync ...\n>>>\n\n"
sleep 5
yum install -y pacemaker pcs
echo "hacluster:hacluster" | chpasswd
systemctl start pcsd
for SERVICE in pcsd corosync pacemaker; do systemctl enable $SERVICE; done


printf "\n>>>\n>>> (STEP 6/6) Configuring MariaDB cluster functionality ...\n>>>\n\n"
sleep 5
pcs cluster auth mariadb-master1.domain.com mariadb-master2.domain.com <<EOF
hacluster
hacluster
EOF

#Disable automatic launch of mariadb.service
systemctl disable mariadb.service

pcs cluster setup --name mariadb-server mariadb-master2.domain.com mariadb-master1.domain.com
pcs cluster start --all
pcs status cluster
pcs property set stonith-enabled=false
pcs property set no-quorum-policy=ignore
pcs reCONFIG create cluster_vip ocf:heartbeat:IPaddr2 ip=192.168.144.20 cidr_netmask=24 nic=eth1 op monitor interval=5s
pcs reCONFIG create mariadb_service systemd:mariadb op monitor interval=5s clone
pcs reCONFIG restart mariadb_service-clone
pcs status


rm -f /CONFIGs/$CONFIG/master2_status
rm -f /CONFIGs/$CONFIG/master1_status


printf "\n>>>\n>>> Finished bootstrapping $VM\n>>>\n\n>>> MariaDB is reachable via:\n>>> USERNAME: root\n>>> PASSWORD: devops\n"
