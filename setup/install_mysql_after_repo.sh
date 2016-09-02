#!/bin/bash  -e

## Rap this all for logging to THERE
(
#
# add error checking (exit on error)
#	with bash, set -e (|| true to continue on error)
#
clear
echo
MAX_TIME=60
WAIT_TIME=0
DEBIAN_FRONTEND=noninteractive

export DEBIAN_FRONTEND

#
# Gather global variable info
#
#	DT is in Year-Month-Day for lexographic search ordering
#	Non-FQDN hostname
#	IP address
#	Default MySQL SID (IP address)
#	Backup directory
# 
DT=`date +%Y%m%d`
my_host=`hostname -s`
my_ip=`host \`hostname\` | sed "s/^.*ress //"`
my_sid=`echo ${my_ip} | sed "s/\.//g"`
my_dbuff_mem=`free -og | grep Mem | awk '{ printf "%-.0f\n", $2 * .7 }'`
my_time_zone=`date +%Z`
backup_dir=/backup/${my_host}
prev_instance=1


#
# test if /data exists
# optional -p to make parent directories
#

if [ `df | grep "/data" | wc -l` -lt 1 ]
then
  echo "Warning: /data does not appear to be a separate mounted partition"
  echo "Are you sure you wish to continue the mysql install?"
  select yn in "Yes" "No"; do
    case $yn in
        Yes ) break;;
        No ) exit 1;;
    esac
  done
fi

#
# use a template for users/credentials
#  and verify they have been set
#
if [ `grep -i password user.template | wc -l` -gt 0 ]
then
    echo "Please update user.template to contain valid passwords for the following mysql users: root, slave"
    exit 1
fi
ROOT_PASS=`grep root user.template | cut -d":" -f 2 | sed "s/^ *//"`
SLAVE_PASS=`grep slave user.template | cut -d":" -f 2 | sed "s/^ *//"`

#
# Give option to backup any existing data that will be removed
#
if [ `ls /data/mysql | wc -l` -gt 0 ]
then

  echo ""
  echo "Warning: /data/mysql appears to have data implying a database has "
  echo "already been installed here!"
  echo ""
  echo "Are you sure you wish to continue the mysql install? "
  echo "Note: "
  echo "1) Continuing will remove all the data under /data/mysql. "
  echo "2) Note: A compressed backup of the directory will be placed under "
  echo "   /${backup_dir}/install_data_dir_backup_${DT}.tar.gz "
  echo ""
 
  select yn in "Yes" "No"; do
    case $yn in
        Yes ) break;;
        No )  exit 1;;
    esac
  done
  mkdir -p ${backup_dir}
  tar -cf - /data/mysql  | gzip -c > ${backup_dir}/install_data_dir_backup_${DT}.tar.gz
  rm -rf /data/mysql/*
  prev_instance=0
fi

echo "Installing latest percona package"

apt-get -y install percona-server-server-5.5 percona-server-client-5.5
mysqld_safe_loc=`which mysqld_safe`

echo "Enabling root login"

mysqladmin -u root password $ROOT_PASS

echo "[client]
user=root
password=$ROOT_PASS
" > /root/.my.cnf


echo "stopping and reconfiguring default mysql setup"

service mysql stop

#
# Make sure mysql stops before continuing
#
MYSQL_STATUS=`service mysql status | grep stopped | wc -l`
WAIT_TIME=0

while [ ${MYSQL_STATUS} -lt 1 ]
do
    sleep 1
    WAIT_TIME=`expr ${WAIT_TIME} + 1`
    if [ ${$WAIT_TIME} -gt ${MAX_TIME} ]
    then
      echo "MySQL did not stop as expected."
      exit 1
    fi
    MYSQL_STATUS=`service mysql status | grep stopped | wc -l`
done

#
# Create data directories and set permissions
#

mkdir -p /data/mysql
mkdir -p /data/mysql-logs
mkdir -p /data/tmp

chown -R mysql:mysql /data/mysql
chown -R mysql:mysql /data/mysql-logs
chown -R mysql:mysql /data/tmp

cp -Rp /var/lib/mysql/* /data/mysql

sed -e "s/mnt/data/" -e "s/server-id.*/server-id = ${my_sid}/" -e "s/innodb_buffer_pool_size.*/innodb_buffer_pool_size=${my_dbuff_mem}G/"  my.cnf.template  > /etc/mysql/my.cnf

#
# Remove unecessary default debian checks
#

sed -e "s/upgrade_system_tables_if_necessary/echo ignore upgrade_system_tables_if_necessary/" -e "s/check_root_accounts/echo ignore check_root_accounts/" -e "s/check_for_crashed_tables/echo ignore check_for_crashed_tables/" /etc/mysql/debian-start > /tmp/debian-start

mv /etc/mysql/debian-start /etc/mysql/debian-start.$$.orig
mv /tmp/debian-start /etc/mysql/debian-start

chmod 755 /etc/mysql/debian-start

#
# Modify mysql init script to include setting oom_adj to -17 on startup
#   - this is to prevent oom_killer from choosing mysql as the process to kill off during memory pressure issues
#   - as killing mysql will likely force a slow innodb recovery process
#

sed -e "s/\(.*\)\(#.*Now.*start.*mysqlcheck.*\)/\1PID=\`pidof mysqld\`; echo -17 \> \/proc\/\$PID\/oom_adj\n\1\2/" /etc/init.d/mysql > /tmp/mysql.init

mv /etc/init.d/mysql /etc/mysql/mysql.init.$$.orig
mv /tmp/mysql.init /etc/init.d/mysql

chmod 755 /etc/init.d/mysql

#
# force mysql to rebuild innodb tablespaces and logs 
#
rm /data/mysql/ib*

if [ ${prev_instance} -a -e ${mysqld_safe_loc} ]
then
	echo " UPDATE mysql.user SET Password=PASSWORD('${ROOT_PASS}') WHERE User='root';
		FLUSH PRIVILEGES; " > /tmp/$$_mysql_install_fix.sql
	mysqld_safe --init-file=/tmp/$$_mysql_install_fix.sql &
	sleep 20

	MYSQL_STATUS=`service mysql status | grep -i uptime | wc -l`
	WAIT_TIME=0

	if [ ${MYSQL_STATUS} -gt 0 ]
	then
		mysql -e "show databases"
	fi
	service mysql stop

	while [ ${MYSQL_STATUS} -lt 1 ]
	do
    		sleep 1
    		WAIT_TIME=`expr ${WAIT_TIME} + 1`
    		if [ ${WAIT_TIME} -gt ${MAX_TIME} ]
    		then
      			echo "MySQL did not stop as expected."
      			exit 1
   		 fi
    		MYSQL_STATUS=`service mysql status | grep stopped | wc -l`
	done
	rm /tmp/$$_mysql_install_fix.sql
fi

echo "starting and verifying mysql setup"

#
# Make sure mysql starts before continuing
#
service mysql start

MYSQL_STATUS=`service mysql status | grep -i uptime | wc -l`
WAIT_TIME=0

while [ ${MYSQL_STATUS} -lt 1 ]
do
    sleep 1
    WAIT_TIME=`expr ${WAIT_TIME} + 1`
    if [ ${WAIT_TIME} -gt 60 ]
    then
      echo "MySQL did not start as expected."
      exit 1
    fi
    MYSQL_STATUS=`service mysql status | grep -i uptime | wc -l`
done

#
# Create users and grants
#
mysql -v --show-warnings -e "show processlist"
mysql -v --show-warnings -e "grant replication client on *.* to status@localhost;"
mysql -v --show-warnings -e "grant replication client, replication slave  on *.* to slave@localhost identified by '${SLAVE_PASS}';"
mysql -v --show-warnings -e "grant replication client, replication slave  on *.* to slave@'%' identified by '${SLAVE_PASS}';"
mysql -v --show-warnings -e "select user,host from mysql.user;"

sleep 1

echo "Setting up backups and heartbeat"

mkdir -p /root/bin
apt-get -y install xtrabackup mailutils percona-toolkit

#
# Update db-heartbeat with Master IP iand SID info
# Set db-heartbeat to start automatically
# Create initial heartbeat table and startup
#
sed -e "s/\(^.*\)_IP=.*/\1_IP=${my_ip}/"  -e "s/\(^.*\)_SID=.*/\1_SID=${my_sid}/" -e "s/\(^.*\)_HOST=.*/\1_HOST=${my_ip}/"  db-heartbeat.init > /etc/init.d/db-heartbeat
mysql -v --show-warnings < db-heartbeat.setup.sql
chmod +x /etc/init.d/db-heartbeat
update-rc.d db-heartbeat defaults 99

pt-heartbeat --create-table -D heartbeat --user=root --master-server-id=${my_sid} --check

service db-heartbeat start

sleep 1

mysql -v --show-warnings -e "select * from heartbeat.heartbeat;"

sleep 1

#
# Update percona logrotate files and change permissions on log files to be read by monyog
#
sed -e "s/\/var\/log/\/data\/mysql-logs/g" -e "s/\(^.*\)endscript/\1chmod +r \/data\/mysql-logs\/*.log\\n\1endscript/" /etc/logrotate.d/percona-server-server-5.5 > /tmp/logrotate.$$
mv /tmp/logrotate.$$ /etc/logrotate.d/percona-server-server-5.5
chmod a+r /data/mysql-logs/*.log


#
# Install backup utilities
#

case ${my_time_zone} in 
      "PDT")  
            echo "Warning: Time Zone is set to PDT.  Will set backups to run at 1AM based on PDT.  Please change after install if that is incorrect."
            sed -e "s/MAILTO=.*/MAILTO=\"root@localhost\"/" -e "s/^0 0/0 1/" ../backup/backup_cronjob > /etc/cron.d/mysql_backup
            sleep 1
            ;;
      "UTC")  
            echo "Time Zone is set to UTC.  Will set backups to run at 8AM UTC/1AM PTD."
            sed -e "s/MAILTO=.*/MAILTO=\"root@localhost\"/" -e "s/^0 0/0 8/" ../backup/backup_cronjob > /etc/cron.d/mysql_backup
            sleep 1
            ;;
       *)    
            echo "Time Zone is set to ${my_time_zone}.  This is not a supported timezone .  Will set backups to run at 1AM ${my_time_zone}.
                    This should be adjusted after the timezone is correctly set on this server."
            sed -e "s/MAILTO=.*/MAILTO=\"root@localhost\"/" -e "s/^0 0/0 1/" ../backup/backup_cronjob > /etc/cron.d/mysql_backup
            sleep 1
            ;;
esac

cp ../backup/mysql_backup_daily.sh /root/bin/
chmod +x /root/bin/*

echo "
	Troubleshoot any errors.  It should be fine to re-run this if the mysql instance had issues during setup.

	The following must be done manually:

	- Modify the mysql configuration in /etc/mysql/my.cnf for specific application requriements and restart mysql
	- Add the application user with appropriate grants to the mysql database
	- If this is not the master, set the backup cron job in /etc/cron.d/mysql_backup to run at the correct time.
		if this is the master, comment out the cron job in the file so that the backups to not run
		run a backup manually (copy from cron command) to verify it works 
	- Modify db-heartbeat for the appropriate master/slave configuration
		file should be updated in /etc/init.d/db-heartbeat
		startup db-heartbeat
	- Comment out the custom debian myisam check on start in /etc/mysql/debian-start
		# echo "Checking for corrupt, not cleanly closed and upgrade needing tables."
		# (
  		# upgrade_system_tables_if_necessary;
  		# check_root_accounts;
  		# check_for_crashed_tables;
		# ) >&2 &

	Type [cntl]-c to quit
"
exit 0
## THERE - complete Rap this all for logging HERE
) 2>&1 | tee -a $0.log
exit 0
