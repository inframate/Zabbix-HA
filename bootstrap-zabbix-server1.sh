#!/bin/sh

CONFIG="zabbix.domain.com"
VM=`cat /etc/hostname`

printf "\n>>>\n>>> WORKING ON: $VM ...\n>>>\n\n>>>\n>>> (STEP 1/5) Configuring system ...\n>>>\n\n\n"
sleep 5
sed -ri 's/127\.0\.0\.1\s.*/127.0.0.1 localhost localhost.localdomain/' /etc/hosts
echo 'root:devops' | chpasswd

sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && service sshd restart
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
echo 0 > /sys/fs/selinux/enforce

printf "\n>>>\n>>> (STEP 2/5) Installing Pacemaker & Corosync ...\n>>>\n\n"
sleep 5
yum install -y pacemaker pcs
echo "hacluster:hacluster" | chpasswd
systemctl start pcsd
for SERVICE in pcsd corosync pacemaker; do systemctl enable $SERVICE; done

printf "\n>>>\n>>> (STEP 3/5) Installing Zabbix Server ...\n>>>\n\n"
sleep 5
yum install -y epel-release
rpm -ivh http://repo.zabbix.com/zabbix/3.2/rhel/7/x86_64/zabbix-release-3.2-1.el7.noarch.rpm
yum install -y zabbix-server-mysql zabbix-java-gateway

printf "\n>>>\n>>> (STEP 4/5) Configuring Zabbix Server ...\n>>>\n\n"
sleep 5
mv /etc/zabbix/zabbix_server.conf /etc/zabbix/zabbix_server.conf.orig
mv /etc/zabbix/zabbix_java_gateway.conf /etc/zabbix/zabbix_java_gateway.conf.orig
cp /CONFIGs/$CONFIG/zabbix_server.conf /etc/zabbix/
cp /CONFIGs/$CONFIG/zabbix_java_gateway.conf /etc/zabbix/

printf "\n>>>\n>>> (STEP 5/5) Configuring Zabbix cluster functionality ...\n>>>\n\n"
sleep 5
pcs cluster auth zabbix-server1.domain.com zabbix-server2.domain.com <<EOF
hacluster
hacluster
EOF
pcs cluster setup --name zabbix-server zabbix-server1.domain.com zabbix-server2.domain.com
pcs cluster start --all
pcs status cluster
pcs property set stonith-enabled=false
pcs property set no-quorum-policy=ignore
pcs reCONFIG create cluster_vip ocf:heartbeat:IPaddr2 ip=192.168.144.15 cidr_netmask=24 nic=eth1 op monitor interval=5s
pcs reCONFIG create zabbix_server systemd:zabbix-server op monitor interval=5s
pcs constraint colocation add zabbix_server cluster_vip
pcs constraint order cluster_vip then zabbix_server
pcs reCONFIG restart zabbix_server
pcs reCONFIG create zabbix_java_gateway systemd:zabbix-java-gateway op monitor interval=10s
pcs constraint colocation add zabbix_java_gateway cluster_vip
pcs constraint order cluster_vip then zabbix_java_gateway
pcs reCONFIG restart zabbix_java_gateway
pcs status

printf "\n>>>\n>>> Finished bootstrapping $VM\n>>>\n\n>>> zabbix-server VIP is reachable via:\n>>> 192.168.144.15\n"
