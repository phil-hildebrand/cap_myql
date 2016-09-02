load "lib/servers.rb"
require 'capistrano/configuration/actions/invocation'

# =====================================================
# SSH OPTIONS
# =====================================================
# You must have both the public and private keys available
# in your .ssh directory

set :use_sudo , true
set :varfile, "/tmp/mysql_cap_variables"
set :local_repo, "."
set :mysql_version , "5.7"
set :mysql_type , "prod"
set :mysql_master , "none"
set :add_user , "none"
set :ssd , "true"
set :scheduler , "noop"
set :mem , "auto"
set :backup , "true"
set :backup_cron , "true"

desc "Show cap options and defaults for input variables"

task :help do
 	puts ''
 	puts 'Usage: cap [--dry-run] <task> [-s options]  <HOSTS|ROLES=hostname|role> \ '
	puts '      -s varfile ( Default=/tmp/mysql_cap_variables) \ '
	puts '      -s local_repo ( Default=/usr/local/src/db-ops/mysql) \ '
	puts '      -s mysql_version ( [5.5|5.6|5.7] Default=5.7 ) \ '
	puts '      -s mysql_type ( [prod|stage|test] Default=prod ) \ '
	puts '      -s mysql_master ( Default=none ex: node_1 ) \ '
	puts '      -s ssd ( Default=true )'
	puts '      -s scheduler ( [noop|deadline|cfq] Default=noop )'
	puts '      -s mem ( in GB - Default=auto - ex: mem=10 )'
	puts '      -s backup ( [true|false] Default=true - enables backups on node )'
	puts '      -s backup_cron ( [true|false] Default=true - install backup cronjob on node )'
 	puts ''
 	puts 'Example: cap --dry-run run_custom -s mysql_type=prod -s mysql_version=5.7'
 	puts ''
end

desc "Show available roles"

task :get_roles do
	output = run_locally "grep -i role #{local_repo}/lib/servers.rb"
      	puts output
end

desc "Get status for the mysql service"

task :check_mysql do
 run "pidof mysqld"
 run "pid=`pidof mysqld`; oom=`cat /proc/${pid}/oom_adj`; if [ $oom != -17 ]; then echo WARNING: $pid not oom protected ($oom); fi"
 run "d_dir=`mysql -u status -N --silent -e \"select variable_value from information_schema.global_variables where variable_name = 'datadir';\"`; if [ \"$d_dir\" != \"/data/mysql/\" ]; then echo FAIL $d_dir; fi"
 run "t_dir=`mysql -u status -N --silent -e \"select variable_value from information_schema.global_variables where variable_name = 'tmpdir';\"`; if [ \"$t_dir\" != \"/data/tmp\" ]; then echo FAIL $t_dir; fi"
end

desc "Setup apt repository"

task :setup_apt_repo do
	run 	"sudo -i; gpg --keyserver hkp://keys.gnupg.net --recv-keys 1C4CBDCDCD2EFD2A"
	run	"sudo -i; gpg -a --export CD2EFD2A | sudo -i apt-key add -"
	# VERSION = Ubuntu release
	run	". /etc/lsb-release; VERSION=\"$DISTRIB_CODENAME\"; \
		 echo \"deb http://repo.percona.com/apt VERSION main\" | sed \"s/VERSION/$VERSION/g\" | sudo -i tee /etc/apt/sources.list.d/percona.list; \
		 echo \"deb-src http://repo.percona.com/apt VERSION main\" | sed \"s/VERSION/$VERSION/g\" | sudo -i tee -a /etc/apt/sources.list.d/percona.list"
	run	"sudo -i apt-get update"
end

task :setup_repl_req do
	run 	"sudo apt-get install -y screen"
	run 	"sudo apt-get install -y netcat"
	run 	"sudo apt-get install -y pv"
end

# , :roles => [ :mysql_active, :mysql_db ] do

task :set_variables do
	if mem == "auto"
		puts "using auto calculations for innodb data buffer cache size"
		run <<-CMD
			sudo sh -c "echo -n my_host: > #{varfile}; hostname -s >> #{varfile}";
			sudo sh -c "echo -n my_ip: >> #{varfile}; hostname -I | cut -d' ' -f1 | head -1 >> #{varfile}";
			xip=`hostname -I | head -1`;
			sudo sh -c "echo -n my_sid: >> #{varfile}; grep my_ip: #{varfile} | sed \'s/my_ip://\' | sed \'s/\\.//g\' >> #{varfile}";
			echo -n my_dbuff_mem: | sudo tee -a #{varfile}; free -og | grep Mem | awk \'{ printf \"%-.0f\\n\", $2 * .7 }\' | sudo tee -a #{varfile};
			sudo sh -c "echo -n my_time_zone: >> #{varfile}; date +\%Z >> #{varfile}";
			sudo sh -c "echo -n \"my_backup_dir:/backup/\" >> #{varfile}; grep my_host: #{varfile} | sed \"s/my_host://\" >> #{varfile}";
			sudo sh -c "echo  my_type: #{mysql_type} >> #{varfile}";
			sudo sh -c "echo  my_version: #{mysql_version} >> #{varfile}";
			sudo chown -f root:root #{varfile}*;
		CMD
	else
		run <<-CMD
			sudo sh -c "echo -n my_host: > #{varfile}; hostname -s >> #{varfile}";
			sudo sh -c "echo -n my_ip: >> #{varfile}; hostname -I | head -1 >> #{varfile}";
			xip=`hostname -I | head -1`;
			sudo sh -c "echo -n my_sid: >> #{varfile}; grep my_ip: #{varfile} | sed \'s/my_ip://\' | sed \'s/\\.//g\' >> #{varfile}";
			sudo sed -e "s/my_dbuff_mem=/my_dbuff_mem=#{mem}/" #{varfile};
			echo my_dbuff_mem:#{mem} | sudo tee -a #{varfile};
			sudo sh -c "echo -n my_time_zone: >> #{varfile}; date +\%Z >> #{varfile}";
			sudo sh -c "echo -n \"my_backup_dir:/backup/\" >> #{varfile}; grep my_host: #{varfile} | sed \"s/my_host://\" >> #{varfile}";
			sudo sh -c "echo  my_type: #{mysql_type} >> #{varfile}";
			sudo sh -c "echo  my_version: #{mysql_version} >> #{varfile}";
			sudo chown -f root:root #{varfile}*;
		CMD
	end
	if mysql_master == "none"
		run <<-CMD
			sudo sh -c "echo -n my_master_ip: >> #{varfile}; sudo hostname -I | cut -d' ' -f1 >> #{varfile}";
			sudo sh -c "echo -n my_master_sid: >> #{varfile}; grep "my_master_ip:" #{varfile} | sed \'s/my_master_ip://\' | sed \'s/\\.//g\' >> #{varfile}";
		CMD
	else
		run <<-CMD
			sudo sh -c "echo -n my_master_ip: >> #{varfile}; sudo host #{mysql_master} | grep address | cut -d\' \' -f 4 | head -1 >> #{varfile}";
			sudo sh -c "echo -n my_master_sid: >> #{varfile}; grep "my_master_ip:" #{varfile} | sed \'s/my_master_ip://\' | sed \'s/\\.//g\' >> #{varfile}";
		CMD
	end
end

task :update_swappiness do
	run <<-CMD
		swappy=`sudo grep "vm.swappiness" /etc/sysctl.conf|wc -l`;
		if [ ${swappy} -lt 1 ];
		then
			echo "No swappy set - (${swappy})";
			sudo chmod 777 /etc/sysctl.conf;
			sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak;
			sudo echo "vm.swappiness = 0" >> /etc/sysctl.conf;
			sudo chmod 644 /etc/sysctl.conf;
			sudo sysctl -p;
		else
			echo "Yes swappy set - (${swappy})";
			sudo sed -i "s/vm.swappiness.*/vm.swappiness = 0/" /etc/sysctl.conf;
			sudo sysctl -p;
		fi;
	CMD
end

task :update_max_files do
	run <<-CMD
		sudo sed -i "s/^# \\(.*pam_limits.so.*\\)/\\1/" /etc/pam.d/su;
		sudo grep pam_limits /etc/pam.d/su;
		files=`sudo grep "fs.nr_open" /etc/sysctl.conf|wc -l`;
		if [ ${files} -lt 1 ];
		then
			echo "No nr_open set - (${files})";
			sudo chmod 777 /etc/sysctl.conf;
			sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak;
			sudo echo "fs.nr_open=5000000" >> /etc/sysctl.conf;
			sudo chmod 644 /etc/sysctl.conf;
			sudo sysctl -p;
		else
			echo "Yes nr_open set - (${files})";
			sudo sed -i "s/fs.nr_open.*/fs.nr_open = 5000000/" /etc/sysctl.conf;
			sudo sysctl -p;
		fi;
		files=`sudo grep "fs.file-max" /etc/sysctl.conf|wc -l`;
		if [ ${files} -lt 1 ];
		then
			echo "No max_files set - (${files})";
			sudo chmod 777 /etc/sysctl.conf;
			sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak;
			sudo echo "fs.file-max=5000000" >> /etc/sysctl.conf;
			sudo chmod 644 /etc/sysctl.conf;
			sudo sysctl -p;
		else
			echo "Yes nr_open set - (${files})";
			sudo sed -i "s/fs.file-max.*/fs.file-max = 5000000/" /etc/sysctl.conf;
			sudo sysctl -p;
		fi;
	CMD
end

task :update_scheduler do
	if ssd == "true"
			# for ssd_drive in `sudo lsblk -ltf -o NAME,MOUNTPOINT|grep -B1 '/data'| perl -e 'while (<>){ if (! /data/ ) {chomp} ;print}'|sed "s/^\([A-Za-z]*\).*\(dm-[0-9*]\).*/\1\n\2/" | cut -d " " -f1`;
		run <<-CMD
			for ssd_drive in `sudo lsblk -ltf -o NAME,MOUNTPOINT|grep -B1 '/data'|grep -v '\\-\\-' | perl -e 'while (<>){ if (! \/data\/ ) {chomp} ;print}'|sed \"s/^\\([A-Za-z]*\\).*\\(dm-[0-9*]\\).*/\\1\\n\\2/" | cut -d " " -f1`;
			do
				echo "Fixing $ssd_drive";
				sudo sh -c "echo 0 >  /sys/block/${ssd_drive}/queue/rotational";
				sudo sh -c "echo noop > /sys/block/${ssd_drive}/queue/scheduler";
			done
		CMD
	else
		puts "No ssd drive, leaving default scheduler"
	end
end

task :disable_apparmor do
	run <<-CMD    
		if [ `which apparmor` ];
		then
                	sudo service apparmor stop ;
			sudo /etc/init.d/apparmor teardown;
                	sudo DEBIAN_FRONTEND=noninteractive sudo update-rc.d -f apparmor remove; 
                	sudo DEBIAN_FRONTEND=noninteractive sudo apt-get remove -y apparmor apparmor-utils;
		fi;
	CMD
end

task :update_configs do

	set_variables
	run <<-CMD
		if [ -f /tmp/my.cnf.template ];
		then
			sudo rm -f /tmp/my.cnf.template;
		fi;
	CMD
	upload( "#{local_repo}/setup/#{mysql_type}_#{mysql_version}_my.cnf.template", "/tmp/my.cnf.template" )
	if mem == "auto"
	then
		run <<-CMD
			DT=`date +%d%m%Y-%H%M%S`
			my_sid=`grep my_sid #{varfile} | sed "s/^.*://"`;
			my_dbuff_mem=`grep my_dbuff_mem #{varfile} | head -1 | sed "s/^.*://"`;
			my_type=`grep my_type #{varfile} | head -1 | sed "s/^.*://"`;

			if [ ${my_type} != "prod" ];
			then
				my_dbuff_mem=`free -og | grep Mem | awk '{ printf "%-.0f\n", $2 * .80 }'`;
			fi;

			if [ ${my_dbuff_mem} -lt 2 ];
			then
				sudo sed -e "s/mnt/data/" -e "s/server-id.*/server-id = ${my_sid}/" -e "s/innodb-buffer-pool-size.*/innodb-buffer-pool-size=128M/"  /tmp/my.cnf.template  > /tmp/my.cnf;
			else
				sudo sed -e "s/mnt/data/" -e "s/server-id.*/server-id = ${my_sid}/" -e "s/innodb-buffer-pool-size.*/innodb-buffer-pool-size=${my_dbuff_mem}G/"  /tmp/my.cnf.template  > /tmp/my.cnf;
			fi;
			if [ -s /etc/mysql/my.cnf ];
			then
				sudo cp -f /etc/mysql/my.cnf /etc/mysql/my.cnf.${DT};
			fi;
			sudo mv /tmp/my.cnf /etc/mysql/my.cnf;
			sudo chown mysql:mysql /etc/mysql/my.cnf;
			sudo rm -f /tmp/my.cnf.template;
		CMD
	else
		run <<-CMD
			DT=`date +%d%m%Y-%H%M%S`
			my_sid=`grep my_sid #{varfile} | sed "s/^.*://"`;
			my_dbuff_mem=`grep my_dbuff_mem #{varfile} | head -1 | sed "s/^.*://"`;
			my_type=`grep my_type #{varfile} | head -1 | sed "s/^.*://"`;
	
			if [ ${my_dbuff_mem} -lt 2 ];
			then
				sudo sed -e "s/mnt/data/" -e "s/server-id.*/server-id = ${my_sid}/" -e "s/innodb-buffer-pool-size.*/innodb-buffer-pool-size=128M/"  /tmp/my.cnf.template  > /tmp/my.cnf;
			else
				sudo sed -e "s/mnt/data/" -e "s/server-id.*/server-id = ${my_sid}/" -e "s/innodb-buffer-pool-size.*/innodb-buffer-pool-size=${my_dbuff_mem}G/"  /tmp/my.cnf.template  > /tmp/my.cnf;
			fi;
			if [ -s /etc/mysql/my.cnf ];
			then
				sudo cp -f /etc/mysql/my.cnf /etc/mysql/my.cnf.${DT};
			fi;
			sudo mv /tmp/my.cnf /etc/mysql/my.cnf ;
			sudo chown mysql:mysql /etc/mysql/my.cnf ;
			sudo rm -f /tmp/my.cnf.template;
		CMD
	end
end

desc "Run custom mysql script ( custom.sql )"

task :run_custom_sql do

 	is_valid = run_locally "cat custom.sql | wc -l"

	puts 'is valid: ' + is_valid

	if is_valid  == '0'
		raise Capistrano::LocalArgumentError, "Fatal Error: Must provide sql statements in custom.sql file!"
	else
		run <<-CMD
		if [ -f /tmp/dba_custom.sql ];
		then
			sudo cp -f /tmp/dba_custom.sql /tmp/dba_custom.sql.bak;
		fi;
		CMD
		upload("custom.sql", "/tmp/dba_custom.sql")

		# Execute grants on server & remove temporary grant scripts
		run "sudo -i mysql -v --show-warnings < /tmp/dba_custom.sql"
		run "sudo rm -f /tmp/dba_custom.sql"
	end
end

desc "Install auto skip replication scripts"

task :install_auto_rep do

	run <<-CMD
		if [ -f /tmp/skip.sql ];
		then
			sudo mv -f /tmp/skip.sql /tmp/skip.sql.bak;
		fi;
		if [ -f /tmp/repl_skip.sh ];
		then
			sudo mv -f /tmp/repl_skip.sh /tmp/repl_skip.sh.bak;
		fi;
		if [ -f /tmp/ignore_slave_errors ];
		then
			sudo mv -f /tmp/ignore_slave_errors /tmp/ignore_slave_errors.bak;
		fi;
	CMD

	upload( "#{local_repo}/setup/skip.sql", "/tmp/skip.sql" )
	upload( "#{local_repo}/setup/repl_skip.sh", "/tmp/repl_skip.sh" )
	upload( "#{local_repo}/setup/ignore_slave_errors", "/tmp/ignore_slave_errors" )

	# Install scripts on server & remove temporary files

	run "sudo mkdir -p /root/bin"
	run "sudo mv /tmp/repl_skip.sh /root/bin"
	run "sudo mv /tmp/skip.sql /root"
	run "sudo chown root:root /root/skip.sql"
	run "sudo chown -R root:root /root/bin"
	run "sudo chmod 700 /root/bin/repl_skip.sh"
	run "sudo mv /tmp/ignore_slave_errors /etc/cron.d"
	run "sudo chown root:root /etc/cron.d/ignore_slave_errors"
	run "sudo chmod 644 /etc/cron.d/ignore_slave_errors"
	run "sudo rm -f /tmp/skip.sql"
	run "sudo rm -f /tmp/repl_skip.sh"
	run "sudo rm -f /tmp/skip.sql"
end

desc "Enable fast shutdown"

task :prep_fast_shutdown do

	run <<-CMD
		if [ -f /tmp/fast_shutdown.sql ];
		then
			sudo cp -f /tmp/fast_shutdown.sql /tmp/fast_shutdown.sql.bak;
			sudo rm -f /tmp/fast_shutdown.sql;
		fi;
	CMD
	upload( "#{local_repo}/setup/fast_shutdown.sql", "/tmp/fast_shutdown.sql" )

	# Execute grants on server & remove temporary grant scripts
	run "sudo -i mysql -v --show-warnings < /tmp/fast_shutdown.sql"
	run "sudo rm -f /tmp/fast_shutdown.sql"
end

task :flush_logs do

	run <<-CMD
		if [ -f /tmp/flush_logs.sql ];
		then
			sudo cp -f /tmp/flush_logs.sql /tmp/flush_logs.sql.bak;
			sudo rm -f /tmp/flush_logs.sql;
		fi;
	CMD
	upload( "#{local_repo}/setup/flush_logs.sql", "/tmp/flush_logs.sql" )

	# Execute grants on server & remove temporary grant scripts
	run "sudo -i mysql -v --show-warnings < /tmp/flush_logs.sql"
	run "sudo rm -f /tmp/flush_logs.sql"
end

desc "Stop Slave Process"

task :stop_slave do

	run <<-CMD
		if [ -f /tmp/stop_slave.sql ];
		then
			sudo cp -f /tmp/stop_slave.sql /tmp/stop_slave.sql.bak;
			sudo rm -f /tmp/stop_slave.sql;
		fi;
	CMD
	upload( "#{local_repo}/setup/stop_slave.sql", "/tmp/stop_slave.sql" )

	# Execute grants on server & remove temporary grant scripts
	run "sudo -i mysql -v --show-warnings < /tmp/stop_slave.sql"
	run "sudo rm -f /tmp/stop_slave.sql"
end

desc "Start Slave Process"

task :start_slave do

	run <<-CMD
		if [ -f /tmp/start_slave.sql ];
		then
			sudo cp -f /tmp/start_slave.sql /tmp/start_slave.sql.bak;
			sudo rm -f /tmp/start_slave.sql;
		fi;
	CMD
	upload( "#{local_repo}/setup/start_slave.sql", "/tmp/start_slave.sql" )

	# Execute grants on server & remove temporary grant scripts
	run "sudo -i mysql -v --show-warnings < /tmp/start_slave.sql"
	run "sudo rm -f /tmp/start_slave.sql"
end

desc "Grant access to standard mysql users"

task :grant_default_access do

 	is_valid = run_locally "grep -i password user.template | wc -l"

	puts 'is valid: ' + is_valid

	if is_valid  == '0'
		raise Capistrano::LocalArgumentError, "Fatal Error: Must provide credential for all users in user.template file!"
	else
		set_variables

		# Get credentials from user.template
		root_pass = run_locally "grep root user.template | cut -d\":\" -f 2 | sed \"s/^ *//\" "
		slave_pass = run_locally "grep slave user.template | cut -d\":\" -f 2 | sed \"s/^ *//\" "
		dba_pass = run_locally "grep dba user.template | cut -d\":\" -f 2 | sed \"s/^ *//\" "

		# Replace grants script with actual credentials
		run_locally "if [ -s /tmp/run_grants.sql.bak ]; then sudo rm -f /tmp/run_grants.sql.bak; fi;"
		run_locally "if [ -s /tmp/run_grants.sql ]; then sudo cp -f /tmp/run_grants.sql /tmp/run_grants.sql.bak; sudo rm -f /tmp/run_grants.sql;fi;"
		run_locally "if [ -s /tmp/run_grants_now.sql.bak ]; then sudo rm -f /tmp/run_grants_now.sql.bak; fi;"
		run_locally "if [ -s /tmp/run_grants_now.sql ]; then sudo cp -f /tmp/run_grants_now.sql /tmp/run_grants_now.sql.bak; sudo rm /tmp/run_grants_now.sql; fi;"
		run_locally "sudo sed -e \"s/slave_pass/#{slave_pass.strip}/g\" -e \"s/dba_pass/#{dba_pass.strip}/g\" #{local_repo}/setup/grants.#{mysql_version}.sql > /tmp/run_grants.sql"
		run "if [ -s /tmp/run_grants.sql.bak ]; then sudo rm -f /tmp/run_grants.sql.bak; fi;"
		run "if [ -s /tmp/run_grants.sql ]; then sudo cp -f /tmp/run_grants.sql /tmp/run_grants.sql.bak; fi;"
		run "if [ -s /tmp/run_grants_now.sql.bak ]; then sudo rm -f /tmp/run_grants_now.sql.bak; fi;"
		run "if [ -s /tmp/run_grants_now.sql ]; then sudo cp -f /tmp/run_grants_now.sql /tmp/run_grants_now.sql.bak; fi;"
		run "if [ -s /tmp/run_grants_now.sql ]; then sudo rm -f /tmp/run_grants_now.sql; fi;"
		upload("/tmp/run_grants.sql", "/tmp/run_grants.sql")

		# Execute grants on server & remove temporary grant scripts
		run "sudo echo hey \`grep my_host #{varfile} | sed \"s/^.*://\"\`"
		run "my_host=\`grep my_host #{varfile} | sed \"s/^.*://\"\`; export my_host;echo host $my_host "
		run "my_host=\`grep my_host #{varfile} | sed \"s/^.*://\"\`; export my_host; sudo sed \"s/my_host/\$my_host/g\" /tmp/run_grants.sql |sudo tee -a /tmp/run_grants_now.sql"
		run "sudo -i mysql -v --show-warnings < /tmp/run_grants_now.sql"
		run "if [ -s /tmp/run_grants.sql ]; then sudo rm -f /tmp/run_grants.sql; fi;"
		run "if [ -s /tmp/run_grants_new.sql ]; then sudo rm -f /tmp/run_grants_new.sql; fi;"
		run_locally "if [ -s /tmp/run_grants.sql]; then sudo rm /tmp/run_grants.sql; fi;"
	end

	if mysql_type == "prod"
		run "echo Skipping custom grants"
	else
		# Get password for non prod environment
		status_pass = run_locally "grep ^status #{mysql_type}.user.template | cut -d\":\" -f 2 | sed \"s/^ *//\" "
		run_locally "sed -e \"s/status_pass/#{status_pass.strip}/g\" #{local_repo}/setup/#{mysql_type}.grants.#{mysql_version}.sql > /tmp/run_grants.sql"
		run "if [ -s /tmp/run_grants.sql ]; then sudo mv -f /tmp/run_grants.sql /tmp/run_grants.sql.bak; fi;"
		run "if [ -s /tmp/run_grants_now.sql ]; then sudo mv -f /tmp/run_grants_now.sql /tmp/run_grants_now.sql.bak; fi;"
		upload("/tmp/run_grants.sql", "/tmp/run_grants.sql")

		# Execute grants on server & remove temporary grant scripts
		run "sudo echo hey \`grep my_host #{varfile} | sed \"s/^.*://\"\`"
		run "my_host=\`grep my_host #{varfile} | sed \"s/^.*://\"\`; export my_host;echo host $my_host "
		run "my_host=\`grep my_host #{varfile} | sed \"s/^.*://\"\`; export my_host; sed \"s/my_host/\$my_host/g\" /tmp/run_grants.sql > /tmp/run_grants_now.sql"
		run "sudo -i mysql -v --show-warnings < /tmp/run_grants_now.sql"
		run "if [ -s /tmp/run_grants.sql ]; then rm /tmp/run_grants.sql; fi;"
		run "if [ -s /tmp/run_grants_now.sql ]; then rm /tmp/run_grants_now.sql; fi;"
		run_locally "if [ -s /tmp/run_grants.sql ]; then rm /tmp/run_grants.sql; fi;"
	end
end

desc "Set variables for credentials"

task :get_credentials do

	my_host = run_locally("hostname -s")
	puts my_host
end


desc "Install MySQL Utilities"

task :install_mysql_utils do
        run <<-CMD
		wget http://dev.mysql.com/get/Downloads/MySQLGUITools/mysql-utilities-1.6.2.tar.gz;
		tar -xvzf mysql-utilities-1.6.2.tar.gz;
		cd mysql-utilities-1.6.2;
		python ./setup.py build;
		sudo python ./setup.py install;
	CMD
end

desc "Update MySQL Backups"

task :update_backups do

	set_variables
	setup_apt_repo

        run <<-CMD
                DEBIAN_FRONTEND=noninteractive;
                export DEBIAN_FRONTEND;
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y install  percona-xtrabackup-24 mailutils percona-toolkit qpress
        CMD

	# Upload backup templates to server
	upload( "#{local_repo}/backup/mysql_backup_daily.sh", "/tmp/mysql_backup_daily.sh" )
	upload( "#{local_repo}/backup/backup_cronjob", "/tmp/backup_cronjob" )
	upload( "#{local_repo}/scripts/check_mysql_backups.sh", "/tmp/check_mysql_backups.sh" )

	# Get timezones and update backup templates for given server's timezone
	run <<-CMD
		my_time_zone=`grep my_time_zone #{varfile} | sed "s/^.*://"`;
		my_sid=`grep my_sid #{varfile} | sed "s/^.*://"`;
		export my_time_zone my_sid;
		case $my_time_zone in
      			"PDT")
				backup_time=`expr $my_sid % 8`;
				export backup_time;
				my_backup_time=`expr $backup_time`;
				export my_backup_time;
        	    		echo "Warning: Time Zone is set to PDT.  Will set backups to run at $my_backup_time AM based on PDT.  Please change after install if that is incorrect.";
            			sed -e "s/MAILTO=.*/# MAILTO=\"root@localhost\"/" -e "s/^0 0/0 $my_backup_time/" /tmp/backup_cronjob > /tmp/mysql_backup;
            			#sleep 1
            			;;
      			"UTC")
				backup_time=`expr $my_sid % 8`;
				export backup_time;
				my_backup_time=`expr 16 - $backup_time`;
				export my_backup_time;
            			echo "Time Zone is set to UTC.  Will set backups to run at $my_backup_time AM UTC.";
            			sed -e "s/MAILTO=.*/# MAILTO=\"root@localhost\"/" -e "s/^0 0/0 $my_backup_time/" /tmp/backup_cronjob > /tmp/mysql_backup;
            			#sleep 1
            			;;
       			*)
				backup_time=`expr $my_sid % 8`;
				export backup_time;
				my_backup_time=`expr 16 - $backup_time`;
				export my_backup_time;
            			echo "Time Zone is set to $my_time_zone.  This is not a supported timezone for.  Will set backups to run at $my_backup_time AM $my_time_zone.  This should be adjusted after the timezone is correctly set on this server.";
            			sed -e "s/MAILTO=.*/# MAILTO=\"root@localhost\"/" -e "s/^0 0/0 $my_backup_time/" /tmp/backup_cronjob > /tmp/mysql_backup;
            			#sleep 1
            		;;
		esac;
	CMD

	# Set backup scripts to be executable and cleanup temporary files
	run "sudo mkdir -p /root/bin"
	run "sudo chown -R root:root /root/bin"
	run "sudo mv /tmp/mysql_backup_daily.sh /root/bin"
	run "sudo mv /tmp/mysql_backup /etc/cron.d"
	run "sudo chmod -f +x /root/bin/mysql_backup_daily.sh"
	run "sudo chown -R root:root /etc/cron.d/mysql_backup"
	run "sudo chmod 0644 /etc/cron.d/mysql_backup"
	run "sudo grep mysql_backup /etc/cron.d/mysql_backup"
	run "sudo rm /tmp/backup_cronjob"
	run "sudo mv /tmp/check_mysql_backups.sh /usr/local/bin"
	run "sudo chmod -f +x /usr/local/bin/check_mysql_backups.sh"
	run "sudo chown root:root /usr/local/bin/check_mysql_backups.sh"
	run "sudo rm -f /tmp/check_mysql_backups.sh"
        if backup == "true"
		puts 'Installing and enabling backups'
	else
		puts 'Installing but not disabling backups'
		run <<-CMD
                	sudo sed -i "s/^/# /" /etc/cron.d/mysql_backup
		CMD
	end
end

desc "Update MySQL Backup Scripts"

task :update_backup_scripts do

	set_variables

	# Upload backup templates to server
	upload( "#{local_repo}/backup/mysql_backup_daily.sh", "/tmp/mysql_backup_daily.sh" )
	upload( "#{local_repo}/backup/backup_cronjob", "/tmp/backup_cronjob" )
	upload( "#{local_repo}/scripts/check_mysql_backups.sh", "/tmp/check_mysql_backups.sh" )

	# Get timezones and update backup templates for given server's timezone
        if backup_cron == "true"
		puts 'Installing backup cron job'
		run <<-CMD
			my_time_zone=`grep my_time_zone #{varfile} | sed "s/^.*://"`;
			my_sid=`grep my_sid #{varfile} | sed "s/^.*://"`;
			export my_time_zone my_sid;
			case $my_time_zone in
      				"PDT")
					backup_time=`expr $my_sid % 8`;
					export backup_time;
					my_backup_time=`expr $backup_time`;
					export my_backup_time;
        	    			echo "Warning: Time Zone is set to PDT.  Will set backups to run at $my_backup_time AM based on PDT.  Please change after install if that is incorrect.";
            				sed -e "s/MAILTO=.*/# MAILTO=\"root@localhost\"/" -e "s/^0 0/0 $my_backup_time/" /tmp/backup_cronjob > /tmp/mysql_backup;
            				#sleep 1
            				;;
      				"UTC")
					backup_time=`expr $my_sid % 8`;
					export backup_time;
					my_backup_time=`expr 16 - $backup_time`;
					export my_backup_time;
            				echo "Time Zone is set to UTC.  Will set backups to run at $my_backup_time AM UTC.";
            				sed -e "s/MAILTO=.*/# MAILTO=\"root@localhost\"/" -e "s/^0 0/0 $my_backup_time/" /tmp/backup_cronjob > /tmp/mysql_backup;
            				#sleep 1
            				;;
       				*)
					backup_time=`expr $my_sid % 8`;
					export backup_time;
					my_backup_time=`expr 16 - $backup_time`;
					export my_backup_time;
            				echo "Time Zone is set to $my_time_zone.  This is not a supported timezone.  Will set backups to run at $my_backup_time AM $my_time_zone.  This should be adjusted after the timezone is correctly set on this server.";
            				sed -e "s/MAILTO=.*/# MAILTO=\"root@localhost\"/" -e "s/^0 0/0 $my_backup_time/" /tmp/backup_cronjob > /tmp/mysql_backup;
            				#sleep 1
            			;;
			esac;
		CMD
		run "sudo mv /tmp/mysql_backup /etc/cron.d"
		run "sudo chown -R root:root /etc/cron.d/mysql_backup"
		run "sudo chmod 0644 /etc/cron.d/mysql_backup"
	else
		puts 'Installing backup scripts,  but not cron job'
	end

	# Set backup scripts to be executable and cleanup temporary files
	run "sudo mkdir -p /root/bin"
	run "sudo chown -R root:root /root/bin"
	run "sudo mv /tmp/mysql_backup_daily.sh /root/bin"
	run "sudo chmod -f +x /root/bin/mysql_backup_daily.sh"
	run "sudo grep mysql_backup /etc/cron.d/mysql_backup"
	run "sudo rm /tmp/backup_cronjob"
	run "sudo mv /tmp/check_mysql_backups.sh /usr/local/bin"
	run "sudo chmod -f +x /usr/local/bin/check_mysql_backups.sh"
	run "sudo chown root:root /usr/local/bin/check_mysql_backups.sh"
	run "sudo rm -f /tmp/check_mysql_backups.sh"
        if backup == "true"
		puts 'Installing and enabling backups'
	else
		puts 'Installing but not disabling backups'
		run <<-CMD
                	sudo sed -i "s/^/# /" /etc/cron.d/mysql_backup
		CMD
	end
end

desc "Startup Percona Heartbeat"

task :start_heartbeat, :on_error => :continue do
	run "sudo service db-heartbeat start >> /dev/null"
	run "sudo -i mysql -v --show-warnings -e 'select * from heartbeat.heartbeat;'"
end

desc "Update Percona Heartbeat"

task :update_heartbeat do

	set_variables

        run <<-CMD
                DEBIAN_FRONTEND=noninteractive;
                export DEBIAN_FRONTEND;
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y install  xtrabackup mailutils percona-toolkit
        CMD
	#
	# Update db-heartbeat with Master IP iand SID info
	# Set db-heartbeat to start automatically
	# Create initial heartbeat table and startup
	#
	upload( "#{local_repo}/setup/db-heartbeat.init", "/tmp/db-heartbeat.init" )
	upload( "#{local_repo}/setup/db-heartbeat.setup.sql", "/tmp/db-heartbeat.setup.sql" )
	run <<-CMD
		my_sid=`grep my_sid #{varfile} | sed "s/^.*://"`;
		my_ip=`grep my_ip #{varfile} | sed "s/^.*://"`;
		my_master_sid=`grep my_master_sid #{varfile} | sed "s/^.*://"`;
		my_master_ip=`grep my_master_ip #{varfile} | sed "s/^.*://"`;
		sed -e "s/\\(^.*\\)SLAVE_IP=.*/\\1SLAVE_IP=${my_ip}/"  -e "s/\\(^.*\\)SLAVE_SID=.*/\\1SLAVE_SID=${my_sid}/" -e "s/\\(^.*\\)SLAVE_HOST=.*/\\1SLAVE_HOST=${my_ip}/"  -e "s/\\(^.*\\)MASTER_IP=.*/\\1MASTER_IP=${my_master_ip}/"  -e "s/\\(^.*\\)MASTER_SID=.*/\\1MASTER_SID=${my_master_sid}/" -e "s/\\(^.*\\)MASTER_HOST=.*/\\1MASTER_HOST=${my_master_ip}/" 
 /tmp/db-heartbeat.init > /tmp/db-heartbeat.init.$$;
		sudo mv /tmp/db-heartbeat.init.$$ /etc/init.d/db-heartbeat;
		sudo -i mysql -v --show-warnings < /tmp/db-heartbeat.setup.sql;
		sudo chmod -f +x /etc/init.d/db-heartbeat;
		sudo update-rc.d db-heartbeat defaults 99;
		sudo -i pt-heartbeat --create-table -D heartbeat --user=root --master-server-id=${my_master_sid} --check;
	CMD
end

desc "Add/Update ulimits"

task :update_ulimits do

        upload("#{local_repo}/setup/#{mysql_type}.limits.conf", "/tmp/limits.conf")
        run "sudo mv /tmp/limits.conf /etc/security/limits.conf"
        run "sudo chown root:root /etc/security/limits.conf"
        run "sudo chmod 644 /etc/security/limits.conf"
end

desc "Enable MySQL Core Dumps"

task :enable_core do
	#
	# Enable core dumps for MySQL
	#
	run "sudo mkdir -p /data/mysql-logs/corefiles"
	run "sudo chmod 777 /data/mysql-logs/corefiles"
	run_locally "echo '#!/bin/sh' > /tmp/enable_core.sh"
	run_locally "echo 'echo /data/mysql-logs/corefiles/core > /proc/sys/kernel/core_pattern' >> /tmp/enable_core.sh"
	run_locally "echo 'echo 1 > /proc/sys/kernel/core_uses_pid' >> /tmp/enable_core.sh"
	run_locally "echo 'echo 2 > /proc/sys/fs/suid_dumpable' >> /tmp/enable_core.sh"
  	run_locally "sudo chmod 777 /tmp/enable_core.sh"
        upload( "/tmp/enable_core.sh", "/tmp/enable_core.sh" )
	run "sudo chown root:root /tmp/enable_core.sh"
	run "sudo chmod 755 /tmp/enable_core.sh"
	run "sudo /tmp/enable_core.sh"
	run "sudo rm -f /tmp/enable_core.sh"
 	run_locally "sudo rm -f /tmp/enable_core.sh"
end

desc "Update Percona Logrotate Scripts"

task :update_logrotate_percona do
	#
	# Update percona logrotate files and change permissions on log files to be read by monyog
	#
        upload("#{local_repo}/setup/percona-server-server-#{mysql_version}.logrotate", "/tmp/percona-server-server-#{mysql_version}")
	run <<-CMD
		sudo mv /tmp/percona-server-server-#{mysql_version} /etc/logrotate.d/percona-server-server-#{mysql_version};
		sudo chown root:root /etc/logrotate.d/percona-server-server-#{mysql_version};
		sudo chmod -f a+r /data/mysql-logs/*.log;
		sudo chown mysql:mysql /data/mysql-logs/*.log;
	CMD

end

desc "Install Qpress"

task :install_qpress do

        run <<-CMD
                DEBIAN_FRONTEND=noninteractive;
                export DEBIAN_FRONTEND;
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y install qpress
        CMD
end

desc "Install MySQL Backups"

task :install_backups do

	run "sudo mkdir -p /root/bin"
        run <<-CMD
                DEBIAN_FRONTEND=noninteractive;
                export DEBIAN_FRONTEND;
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y install percona-xtrabackup-24 mailutils percona-toolkit qpress
        CMD
	# Upload backup templates to server
	upload( "#{local_repo}/backup/mysql_backup_daily.sh", "/tmp/mysql_backup_daily.sh" )
	upload( "#{local_repo}/backup/backup_cronjob", "/tmp/backup_cronjob" )

	# Get timezones and update backup templates for given server's timezone
	run <<-CMD
		my_time_zone=`grep my_time_zone #{varfile} | sed "s/^.*://"`;
 		my_sid=`grep my_sid #{varfile} | sed "s/^.*://"`;
  		export my_time_zone my_sid;
		echo host $my_time_zone $my_sid;
                case $my_time_zone in
                        "PDT")
                                backup_time=`expr $my_sid % 8`;
                                export backup_time;
                                my_backup_time=`expr $backup_time`;
                                export my_backup_time;
                                echo "Warning: Time Zone is set to PDT.  Will set backups to run at $my_backup_time AM based on PDT.  Please change after install if that is incorrect.";
                                sed -e "s/MAILTO=.*/# MAILTO=\"root@localhost\"/" -e "s/^0 0/0 $my_backup_time/" /tmp/backup_cronjob > /tmp/mysql_backup;
                                #sleep 1
                                ;;
                        "UTC")
                                backup_time=`expr $my_sid % 8`;
                                export backup_time;
                                my_backup_time=`expr 16 - $backup_time`;
                                export my_backup_time;
                                echo "Time Zone is set to UTC.  Will set backups to run at $my_backup_time AM UTC.";
                                sed -e "s/MAILTO=.*/# MAILTO=\"root@localhost\"/" -e "s/^0 0/0 $my_backup_time/" /tmp/backup_cronjob > /tmp/mysql_backup;
                                #sleep 1
                                ;;
                        *)
                                backup_time=`expr $my_sid % 8`;
                                export backup_time;
                                my_backup_time=`expr 16 - $backup_time`;
                                export my_backup_time;
                                echo "Time Zone is set to $my_time_zone.  This is not a supported timezone.  Will set backups to run at $my_backup_time AM $my_time_zone.  This should be adjusted after the timezone is correctly set on this server.";
                                sed -e "s/MAILTO=.*/# MAILTO=\"root@localhost\"/" -e "s/^0 0/0 $my_backup_time/" /tmp/backup_cronjob > /tmp/mysql_backup;
                                #sleep 1
                        ;;
                esac;
	CMD

	# Set backup scripts to be executable and cleanup temporary files
	run <<-CMD
		sudo chown -R root:root /root/bin;
		sudo mv /tmp/mysql_backup_daily.sh /root/bin;
		sudo mv /tmp/mysql_backup /etc/cron.d;
		sudo chmod -f +x /root/bin/mysql_backup_daily.sh;
		sudo chown root:root /etc/cron.d/mysql_backup;
		sudo chmod 644 /etc/cron.d/mysql_backup;
		grep mysql_backup /etc/cron.d/mysql_backup;
		sudo rm /tmp/backup_cronjob;
		sudo mkdir -p /backup;
		sudo sh -c 'echo "dalsan01b:/vol/vol_dbbackups/qt_dbbackup1 /backup nfs defaults 0 0" >> /etc/fstab';
	CMD
        if backup == "true"
		puts 'Installing and enabling backups'
	else
		puts 'Installing but not disabling backups'
		run <<-CMD
                	sudo sed "s/^/# /" /etc/cron.d/mysql_backup
		CMD
	end
	puts 'TBD: you still need to mount the backup dir: sudo mount -a;'
end

desc "Stop mysql"

task :stop_mysql do

	#
	# Make sure mysql stops before continuing
	#
	run <<-CMD
    		sudo service mysql stop;
		MYSQL_STATUS=`sudo service mysql status | grep -i -e 'unrecognized' -e 'stopped' -e 'not running'| wc -l`;
		WAIT_TIME=0;
		MAX_TIME=60;
		while [ ${MYSQL_STATUS} -lt 1 ];
		do
    			sleep 10;
    			WAIT_TIME=`expr ${WAIT_TIME} + 1`;
    			if [ ${WAIT_TIME} -gt ${MAX_TIME} ];
			then
      				echo "MySQL did not stop as expected... waited 10 minutes.";
      				exit 1;
    			fi;
    			MYSQL_STATUS=`sudo service mysql status | grep -i -e 'unrecognized' -e 'stopped' -e 'not running'| wc -l`;
		done
	CMD
end

desc "Start mysql"

task :start_mysql do

	#
	# Make sure mysql starts before continuing
	#
	run <<-CMD
                if [ ! -d /etc/mysql/conf.d ];
                then
                        sudo mkdir -p /etc/mysql/conf.d;
                fi;
		sudo chown mysql:mysql /var/run/mysqld;
		MYSQL_STATUS=`sudo service mysql status | grep -i -e 'uptime' -e 'is running'| wc -l`;
		if [ ${MYSQL_STATUS} -lt 1 ];
		then
    			sudo service mysql start;
			WAIT_TIME=0;
			MAX_TIME=60;
			while [ ${MYSQL_STATUS} -lt 1 ];
			do
    				sleep 10;
    				WAIT_TIME=`expr ${WAIT_TIME} + 1`;
    				if [ ${WAIT_TIME} -gt ${MAX_TIME} ];
				then
      					echo "MySQL did not start as soon expected... waited 10 minutes. Assuming it is just taking a long time";
      					exit 0;
    				fi;
    				MYSQL_STATUS=`sudo service mysql status | grep -i -e 'uptime' -e 'is running' | wc -l`;
			done
		fi;
	CMD
end

desc "Drop test database"

task :drop_test_db do
 run "sudo -i mysql -e 'drop database if exists test;'"
end

desc "Only Install MySQL (percona) "

task :only_install_mysql_percona do
 	run <<-CMD
                DEBIAN_FRONTEND=noninteractive;
                export DEBIAN_FRONTEND;
                sudo echo 'percona-server-server-#{mysql_version} percona-server-server-#{mysql_version}/root-pass password testing' | sudo debconf-set-selections;
                sudo echo 'percona-server-server-#{mysql_version} percona-server-server-#{mysql_version}/re-root-pass password testing' | sudo debconf-set-selections;
                sudo apt-get -y install percona-server-server-#{mysql_version} percona-server-client-#{mysql_version};
        CMD
end


desc "Install MySQL (percona) "

task :install_mysql_percona do

	set_variables
        disable_apparmor
	setup_apt_repo
        setup_repl_req
	update_ulimits
	update_swappiness
	update_max_files

	# If mysql data exists, back it up!
	run <<-CMD
		backup_dir=`grep my_backup_dir #{varfile} | sed "s/^.*://"`;
		DT=`date +%Y%m%d`
		#export backup_dir DT;
		if [ ! -d ${backup_dir} ];
		then
  			sudo mkdir -p ${backup_dir};
			sudo chmod -f 777 ${backup_dir};
		else
			sudo chmod -f 777 ${backup_dir};
		fi;
		if [ -d '/data/mysql' ];
		then
			echo " Warning: /data/mysql already exists.  Backing up directory to  ${backup_dir}/install_data_dir_backup_${DT}.tar.gz ";
  			sudo mkdir -p ${backup_dir};
  			sudo tar -cf - /data/mysql  | sudo gzip -c > ${backup_dir}/install_data_dir_backup_${DT}.tar.gz;
  			sudo rm -rf /data/mysql/*;
 			sudo chmod 775 /data/mysql;
                        # UnInstalling previous percona package
                        sudo DEBIAN_FRONTEND=noninteractive apt-get -y --purge remove percona-server-server-#{mysql_version} percona-server-client-#{mysql_version} percona-server-common-#{mysql_version}
		else
 			sudo mkdir -p /data/mysql;
 			sudo chmod 775 /data/mysql;
		fi;
		if [ ! -d /etc/mysql/conf.d ];
		then
  			sudo mkdir -p /etc/mysql/conf.d;
 			sudo chmod 775 /etc/mysql/conf.d;
		fi;
	CMD
	# Installing latest percona package

	# Fix for Bug: https://bugs.launchpad.net/percona-server/+bug/1206648
	run <<-CMD
		if [ ! -d /etc/mysql/conf.d ];
		then
  			sudo mkdir -p /etc/mysql/conf.d;
 			sudo chmod 775 /etc/mysql/conf.d;
	                sudo chmod 777 /data;
		fi;
	CMD

	root_pass = run_locally "grep root user.template | cut -d\":\" -f 2 | sed \"s/^ *//\" "
	run_locally "echo 'Enabling root login #{root_pass}'"
	run "sudo rm -f /root/.my.cnf"
	run_locally "echo 'Changing root pass for #{mysql_version}'"
	run <<-CMD
		sudo echo "[client]" > /tmp/.my.cnf;
		sudo echo "user=root" >> /tmp/.my.cnf;
		sudo echo "password=#{root_pass}" >> /tmp/.my.cnf;
		sudo echo "port=3306" >> /tmp/.my.cnf;
		sudo echo "[mysqladmin]" >> /tmp/.my.cnf;
		sudo echo "port=3306" >> /tmp/.my.cnf;

		sudo mv /tmp/.my.cnf /root/.my.cnf;
		sudo chown root:root /root/.my.cnf;
		sudo cat /root/.my.cnf;
	CMD
	if mysql_version != 5.7
	        run_locally "echo 'Changing root pass for #{mysql_version} == 5.6'"
 		run <<-CMD
                	DEBIAN_FRONTEND=noninteractive;
                	export DEBIAN_FRONTEND;
                	sudo echo 'percona-server-server-#{mysql_version} percona-server-server/root_password password #{root_pass}' | sudo debconf-set-selections;
                	sudo echo 'percona-server-server-#{mysql_version} percona-server-server/root_password_again password #{root_pass}' | sudo debconf-set-selections;
                	sudo debconf-set-selections| grep percona-server | grep root_password;
                	sudo apt-get -y install percona-server-server-#{mysql_version} percona-server-client-#{mysql_version};
                        # sudo sed -i "s/^/## - /" /etc/mysql/debian-start
        	CMD
	else
	        run_locally "echo 'Changing root pass for #{mysql_version} == 5.7'"
 		run <<-CMD
                	DEBIAN_FRONTEND=noninteractive;
                	export DEBIAN_FRONTEND;
                	sudo echo 'percona-server-server-#{mysql_version} percona-server-server-#{mysql_version}/root-pass password #{root_pass}' | sudo debconf-set-selections;
                	sudo echo 'percona-server-server-#{mysql_version} percona-server-server-#{mysql_version}/re-root-pass password #{root_pass}' | sudo debconf-set-selections;
                	sudo debconf-set-selections| grep percona-server | grep root-password;
                	sudo apt-get -y install percona-server-server-#{mysql_version} percona-server-client-#{mysql_version};
                        # sudo sed -i "s/^/## - /" /etc/mysql/debian-start
        	CMD
	end
	run <<-CMD
		if [ ! -s /etc/mysql/my.cnf ];
		then
			my_host=`grep my_host #{varfile} | sed "s/^.*://"`;
			sudo echo "[mysqld]" | sudo tee /etc/mysql/my.cnf;
			sudo echo "datadir=/var/lib/mysql/" | sudo tee -a /etc/mysql/my.cnf;
			sudo echo "pid-file=/var/lib/mysql/${my_host}.pid" | sudo tee -a /etc/mysql/my.cnf;
			sudo echo "log-error=/var/log/mysql/error.log" | sudo tee -a /etc/mysql/my.cnf;
   		fi;
	CMD
	run_locally "echo 'stopping and reconfiguring default mysql setup'"
	stop_mysql
	if mysql_version == 5.7
		run <<-CMD
                	sudo sed -i "s/MYSQLRUN=.*/MYSQLRUN=\\/var\\/run\\/mysqld/" /etc/init.d/mysql;
                	sudo sed -i "s/MYSQLFILES=.*/MYSQLFILES=\\/data\\/mysql-files/" /etc/init.d/mysql;
                	sudo sed -i "s/MYSQLLOG=.*/MYSQLLOG=\\/data\\/mysql-logs/" /etc/init.d/mysql;
                	sudo sed -i "s/\\(^.*datadir \\).*/\\1 \\"\\/data\\/mysql\\")/" /etc/init.d/mysql;
                        # sudo sed -i "s/ output=.*/ output=`echo ignoring debian-start`" /etc/init.d/mysql;
		CMD
	end
	run <<-CMD
		sudo chown root:root /root/.my.cnf;
	CMD
	run <<-CMD
		sudo echo "[client]" > /tmp/.my.cnf;
		sudo echo "user=root" >> /tmp/.my.cnf;
		sudo echo "password=#{root_pass}" >> /tmp/.my.cnf;
		sudo echo "port=3306" >> /tmp/.my.cnf;
		sudo echo "socket=/data/mysql/mysql.sock" >> /tmp/.my.cnf;
		sudo echo "[mysqladmin]" >> /tmp/.my.cnf;
		sudo echo "port=3306" >> /tmp/.my.cnf;
		sudo echo "socket=/data/mysql/mysql.sock" >> /tmp/.my.cnf;

		sudo mv /tmp/.my.cnf /root/.my.cnf;
		sudo chown root:root /root/.my.cnf;
		sudo cat /root/.my.cnf;
	CMD
	#
	# Install pirosshki keys
	#
	if mysql_type != "prod"
                install_pirosshki_key
        end
	#
	# Enable core dumps for vanguard prod
	#
	if mysql_type == "prod"
		enable_core
	else
		run "echo Skip enabling [master] core dumps"
	end
	#
	# Create data directories and set permissions
	#
	upload( "#{local_repo}/setup/#{mysql_type}_#{mysql_version}_my.cnf.template", "/tmp/my.cnf.template" )
	run <<-CMD
		my_sid=`grep my_sid #{varfile} | sed "s/^.*://"`;
		my_dbuff_mem=`grep my_dbuff_mem #{varfile} | head -1 | sed "s/^.*://"`;
		data_dir=`df -h | grep /data | wc -l`;
    		if [ ${data_dir} -lt 1 ];
		then
			sudo rm -rf /data;
			sudo mkdir -p /var/data;
			sudo ln -s /var/data /data;
		fi;
		sudo mkdir -p /data/mysql;
		sudo mkdir -p /data/mysql-logs;
		sudo mkdir -p /data/tmp;
		sudo mkdir -p /data/mysql-files;

		sudo chmod 755 /var/lib/mysql;
		sudo cp -Rp /var/lib/mysql/* /data/mysql;
		if [ -d /var/lib/mysql-files ];
		then
			sudo cp -Rp /var/lib/mysql-files/* /data/mysql-files;
		fi;
	
		sudo chown -R mysql:mysql /data/mysql;
		sudo chown -R mysql:mysql /data/mysql-logs;
		sudo chown -R mysql:mysql /data/mysql-files;
		sudo chown -R mysql:mysql /data/tmp;

		sudo chmod 755 /data/mysql;
		sudo chmod 755 /data/mysql-logs;
		sudo chmod 755 /data/mysql-files;
		sudo chmod 775 /data/tmp;

		sudo chmod -f a+r /data/mysql-logs/*.log;
	
		if [ ${my_dbuff_mem} -lt 2 ];
		then
			sudo sed -e "s/mnt/data/" -e "s/server-id.*/server-id = ${my_sid}/" -e "s/innodb-buffer-pool-size.*/innodb-buffer-pool-size=128M/" /tmp/my.cnf.template  > /tmp/my.cnf;
		else
			sudo sed -e "s/mnt/data/" -e "s/server-id.*/server-id = ${my_sid}/" -e "s/innodb-buffer-pool-size.*/innodb-buffer-pool-size=${my_dbuff_mem}G/" /tmp/my.cnf.template  > /tmp/my.cnf;
		fi;
		sudo mv /tmp/my.cnf /etc/mysql/my.cnf;
		sudo chown mysql:mysql /etc/mysql/my.cnf;
	CMD
	#
	# Remove unecessary default debian checks
	#
	run <<-CMD
		if [ -s /etc/mysql/debian-start ];
		then
			sudo sed -e "s/upgrade_system_tables_if_necessary/echo ignore upgrade_system_tables_if_necessary/" -e "s/check_root_accounts/echo ignore check_root_accounts/" -e "s/check_for_crashed_tables/echo ignore check_for_crashed_tables/" /etc/mysql/debian-start > /tmp/debian-start;
			sudo mv /etc/mysql/debian-start /etc/mysql/debian-start.$$.orig;
			sudo mv /tmp/debian-start /etc/mysql/debian-start;
			sudo chmod -f 755 /etc/mysql/debian-start;
		fi;
	CMD
	#
	# Modify mysql init script to include setting oom_adj to -17 on startup
	#   - this is to prevent oom_killer from choosing mysql as the process to kill off during memory pressure issues
	#   - as killing mysql will likely force a slow innodb recovery process
	#
	if mysql_version != 5.7
		run <<-CMD
			sudo sed -e "s/\\(.*\\)\\(#.*Now.*start.*mysqlcheck.*\\)/\\n\\1PID=\\`pidof mysqld\\`; echo -17 \> \\/proc\\/\\$PID\\/oom_adj \\n\\1\\2 /" -e "s/mysqladmin --defaults-file=.*/mysqladmin --defaults-file=\\/root\\/\\.my\\.cnf\\"/" -e "s/\\(.*\\)sanity_checks;/\\1sanity_checks; \\n\\1ulimit -c unlimited;\\n /" /etc/init.d/mysql > /tmp/mysql.init.$$;
                	# sudo sed -i "s/ output=.*/ output=`echo ignoring debian-start`" /tmp/mysql.init.$$;
			sudo mv -f /etc/init.d/mysql /etc/mysql/mysql.init.$$.orig;
			sudo mv -f /tmp/mysql.init.$$ /etc/init.d/mysql;
			sudo chmod -f 755 /etc/init.d/mysql;
			sudo chown root:root /etc/init.d/mysql;
		CMD
	end
	#
	# force mysql to rebuild innodb tablespaces and logs
	#
	run "sudo rm -vf /data/mysql/ib_log*"
	start_mysql
	update_logrotate_percona
	grant_default_access
	update_heartbeat
	install_monyog_key
	install_backups
	update_scheduler
	start_heartbeat
	drop_test_db
	install_auto_rep
	install_mysql_utils
end

desc "Update MySQL (percona) to latest patch set"

task :patch_mysql_percona do

	set_variables
	setup_apt_repo
	stop_slave
	prep_fast_shutdown
	run_locally "sleep 300"
	flush_logs
	run_locally "echo 'Stopping and patching mysql'"
        stop_mysql

	# Installing latest percona package

	# Fix for Bug: https://bugs.launchpad.net/percona-server/+bug/1206648
	run <<-CMD
		if [ ! -d /etc/mysql/conf.d ];
		then
  			sudo mkdir -p /etc/mysql/conf.d;
 			sudo chmod 775 /etc/mysql/conf.d;
		fi;
	CMD

	root_pass = run_locally "grep root user.template | cut -d\":\" -f 2 | sed \"s/^ *//\" "
        #
	# Move original database backup location and upgrade new mysql instance
        #  to workaround the issue with mysql taking too long to start and
        #  apt-get patches failing.
        #
	run <<-CMD
		if [ ! -d /data/mysql ];
		then
  			echo "Failed - data dir /data/mysql not found";
                        exit 1;
		fi;
		if [ -d /data/mysql_back ];
                then
  			echo "Failed - data dir /data/mysql_back already exists";
                        exit 1;
		fi;
                sudo mv /data/mysql /data/mysql_back;
                sudo mkdir -p /data/mysql;
                sudo chown -R mysql:mysql /data/mysql;
                #
                # mysql_install_db sets a blank local password for root
                #  so we need to save our original one
                #
                sudo mysql_install_db;
                sudo cp /root/.my.cnf /tmp/.my.cnf;
                sudo sed -i "s/password=.*/password=/" /root/.my.cnf;
                sudo apt-get clean;
                sudo apt-get update;
		DEBIAN_FRONTEND=noninteractive;
		export DEBIAN_FRONTEND;
		sudo DEBIAN_FRONTEND=noninteractive apt-get -y install percona-server-server-#{mysql_version} percona-server-client-#{mysql_version} -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" ;
	CMD
        stop_mysql
	#
	# Remove unecessary default debian checks
	#
	run <<-CMD
		sudo sed -e "s/upgrade_system_tables_if_necessary/echo ignore upgrade_system_tables_if_necessary/" -e "s/check_root_accounts/echo ignore check_root_accounts/" -e "s/check_for_crashed_tables/echo ignore check_for_crashed_tables/" /etc/mysql/debian-start > /tmp/debian-start;
		sudo mv /etc/mysql/debian-start /etc/mysql/debian-start.$$.orig;
		sudo mv /tmp/debian-start /etc/mysql/debian-start;
		sudo chmod -f 755 /etc/mysql/debian-start;
	CMD
	#
	# Modify mysql init script to include setting oom_adj to -17 on startup
	#   - this is to prevent oom_killer from choosing mysql as the process to kill off during memory pressure issues
	#   - as killing mysql will likely force a slow innodb recovery process
	#
	run <<-CMD
		sudo sed -e "s/\\(.*\\)\\(#.*Now.*start.*mysqlcheck.*\\)/\\n\\1PID=\\`pidof mysqld\\`; echo -17 \> \\/proc\\/\\$PID\\/oom_adj \\n\\1\\2 /" -e "s/mysqladmin --defaults-file=.*/mysqladmin --defaults-file=\\/root\\/\\.my\\.cnf\\"/" -e "s/\\(.*\\)sanity_checks;/\\1sanity_checks; \\n\\1ulimit -c unlimited;\\n /" -e "s/log_end_message 1/log_end_message 0/" /etc/init.d/mysql > /tmp/mysql.init.$$;
                # sudo sed -i "s/ output=.*/ output=`echo ignoring debian-start`" /tmp/mysql.init.$$;
		sudo mv -f /etc/init.d/mysql /etc/mysql/mysql.init.$$.orig;
		sudo mv -f /tmp/mysql.init.$$ /etc/init.d/mysql;
		sudo chmod -f 755 /etc/init.d/mysql;
		sudo chown root:root /etc/init.d/mysql;
	CMD
	# Move back original database from backup
	run <<-CMD
		if [ -d /data/mysql_tmp ];
		then
  			echo "Failed - tmp dir already exists - removing";
                        sudo rm -rf /data/mysql_tmp;
		fi;
                sudo mv /data/mysql /data/mysql_tmp;
                sudo mv /data/mysql_back /data/mysql;
                sudo mv /tmp/.my.cnf /root/.my.cnf;
	CMD
        start_mysql
        run "sudo rm -rf /data/mysql_tmp"
end
