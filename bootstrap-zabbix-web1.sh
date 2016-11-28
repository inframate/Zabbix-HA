#!/bin/sh

CONFIG="zabbix.domain.com"
VM=`cat /etc/hostname`

printf "\n>>>\n>>> WORKING ON: $VM ...\n>>>\n\n>>>\n>>> (STEP 1/3) Configuring system ...\n>>>\n\n\n"
sleep 5
sed -ri 's/127\.0\.0\.1\s.*/127.0.0.1 localhost localhost.localdomain/' /etc/hosts
echo 'root:devops' | chpasswd

sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config && service sshd restart
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux
echo 0 > /sys/fs/selinux/enforce

printf "\n>>>\n>>> (STEP 2/3) Installing Zabbix Web ...\n>>>\n\n"
sleep 5
yum install -y epel-release
yum update
rpm -ivh http://repo.zabbix.com/zabbix/3.2/rhel/7/x86_64/zabbix-release-3.2-1.el7.noarch.rpm
yum install -y httpd mod_ssl php zabbix-web-mysql

printf "\n>>>\n>>> (STEP 3/3) Configuring Zabbix Web ...\n>>>\n\n"
sleep 5
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=NL/ST=Denial/L=Amsterdam/O=Dis/CN=www.domain.com" -keyout /etc/pki/tls/private/zabbix.key -out /etc/pki/tls/private/zabbix.crt >/dev/null 2>&1
mv /etc/php.ini /etc/php.ini.orig
cp /CONFIGs/$CONFIG/php.ini /etc/
cp /CONFIGs/$CONFIG/zabbix.conf.php /etc/zabbix/web/
sed -i 's/Listen 443 https/#Listen 443 https/' /etc/httpd/conf.d/ssl.conf
mv /etc/httpd/conf.d/zabbix.conf /etc/httpd/conf.d/zabbix.conf.orig
cp /CONFIGs/$CONFIG/zabbix-vhost.conf /etc/httpd/conf.d/
systemctl start httpd && systemctl enable httpd

printf "\n>>>\n>>> Finished bootstrapping $VM\n"
