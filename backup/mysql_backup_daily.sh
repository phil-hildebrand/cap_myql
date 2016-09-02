#!/bin/bash -e
# set -x
#
# See devops/mysql/backup/license.txt for the license to this application.  
# Original work by BlueGecko, enhancements by Moz dba team

# ######################################################################## 
# Beginning of user-configurable section
# ######################################################################## 

# *** SET BACKUP_DIR ***
# Path for backups
my_host=`hostname -s`
is_ver_57=`sudo service mysql status|grep 5.7|wc -l`
backup_dir=/backup/${my_host}
retention=$1
throttle=$2
schema_dump=$3
pause_slave=$4

if [[ $1 == "-?" ||  $1 == "--help" || $1 == "-help" ]]; then
  echo "
Usage: $0 [throttle] [schema_dump] [pause_slave]

 Option                 Default / Info
 -------------------   -------------------------------------------------------
 retention              [3]           Limit number of saved backups to X

 throttle               [25]          Limit number of iops to X
                                       (Bug in 5.7 means throttle is ignored)

 schema_dump            [true]        Do a schema dump as well to support
                                       table only restores

 pause_slave            [false]       'true' will pause replication for the
                                       duration of the backup

 Example - Limit IOPS to 200, include a schme dump, and pause replication:

   root shell> $0 200 true true
        "
  logit "Failed - Usage Error"
  logit "=== End of Backup ==="
  exit 1
fi


if [ ! $retention ]; then
  retention=3
fi

if [ ! $throttle ]; then
  throttle=25
fi

if [ ! $schema_dump ]; then
  schema_dump="true"
fi

if [ ! $pause_slave ]; then
  pause_slave="false"
fi

mkdir -p ${backup_dir}
chown root:adm ${backup_dir}
chmod 775 ${backup_dir}

# For notification of backup failures
mail_contact=root@localhost

# Path for logging
backup_log_dir=/var/log/
backup_log=/var/log/mysql_backup.log

# xtrabackup version to use.
# Valid options are: xtrabackup_51, xtrabackup_55, or auto.  Default to mysql 5.5.
xtrabackup_version=auto

# Set to 1 to compress backups. If enabled, most recent backup will exist both
# compressed and uncompressed for quick recovery.
compression=1

# Set the compressor to use, defaults to gzip.  Other good options include bzip2
# and pbzip2 (parallel bzip2); make sure to set compressorext to match the tool 
# you're using.  gz for gzip, bz2 for [p]bzip2.
compressor=gzip
compressorext=gz


# S3: This method uploads completed backups to s3 for storage
# REQUIRES: compression=1
# NOTE: Do NOT use slashes in s3_bucket or s3_prefix
s3=0
s3cmd=/usr/bin/s3cmd
s3_bucket=my_bukket
s3_prefix=backups
# 1 for regular reliability, 0 for (cheaper) reduced reliability
s3_reliability=1

# Set to 1 to enable archiving. This is useful for copying backups elsewhere
# with more complex retention rules
archive=0
archive_days=3
archive_user=root
archive_host=remote-host-ip/hostname
archive_port=22
archive_dir=/backup/databases/databasename

# Date formats
date_stamp=`/bin/date "+%Y-%m-%d"`
yesterday_date_stamp=`/bin/date -d yesterday "+%Y-%m-%d"`

# ######################################################################## 
# End of user-configurable section
# ######################################################################## 

s3_archive() {
  hostname=`hostname`
  backup_file=$1

  # If we're not doing s3 backups, then get lost.
  if [ $s3 -eq 0 ]; then
    return
  fi

  if [ $compression -eq 0 ]; then
    logit "WARNING: compression disabled, cannot upload s3 backup"
    return
  fi

  if [ ! -f $s3cmd ]; then
    logit "WARNING: No s3cmd means no s3 archive."
    return
  fi

  # We have a file, let's upload it to the s3 bucket we like.
  s3extracmd=""
  if [ $s3_reliability -eq 1 ]; then
    s3extracmd="--rr"
  fi

  logit "Uploading backup to s3..."
  $s3cmd $s3extracmd put $backup_dir/$backup_file s3://$s3_bucket/$s3_prefix/$hostname-$backup_file >>$backup_log 2>&1
  if [ $? -eq 0 ]; then
    logit "Upload complete"
  else
    logit "Upload failed"
  fi

}


logit() {
    echo `date "+%Y-%m-%d %H:%M:%S"` "[*] $1" >>$backup_log
}

cleanup() {
    # Delete old local backups according to the retention policy
    if [ ! $retention ]; then
        logit "Retention unset -- assuming 0."
        retention=0
    fi

    # Only keep $retention backups
    if [ $retention -gt 0 ]; then
        num_backups=`find -L $backup_dir -name '*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'$ext -print | wc -l`
        logit "Retention is $retention. Found $num_backups backups."
    
        while [ $num_backups -gt $retention ]; do
            oldest_backup=`find -L $backup_dir -name '*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'$ext -print | sort | head -n1`
            logit "Deleting oldest backup: $oldest_backup"
            rm -rf $oldest_backup
    
            num_backups=`find -L $backup_dir -name '*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'$ext -print | wc -l`
            logit "Retention is $retention. Found $num_backups backups."
        done
        # Only keep $retention backup directories
        num_backups=`find -L $backup_dir -name '*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' -print | wc -l`
        logit "Retention is $retention. Found $num_backups uncompressed backup directories."
        while [ $num_backups -gt $retention ]; do
            oldest_backup=`find -L $backup_dir -name '*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' -print | sort | head -n1`
            logit "Deleting oldest backup directory: $oldest_backup"
            rm -rf $oldest_backup
    
            num_backups=`find -L $backup_dir -name '*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' -print | wc -l`
            logit "Retention is $retention. Found $num_backups backups."
        done
    else
        logit "Retention of 0 (unlimited)."
    fi
    
#    # Copy backups to a remote location
#    if [ $archive -eq 1 ]; then
#        logit "Archiving enabled. Keeping $archive_days daily backups on $archive_host in $archive_dir."
#    
#        if ! ssh -p$archive_port $archive_user@$archive_host "mkdir -p $archive_dir"; then
#            bail_msg = "Couldn't create $archive_dir on $archive_host."
#            echo `date "+%Y-%m-%d %H:%M:%S"` "[!] $bail_msg" 
#            echo `date "+%Y-%m-%d %H:%M:%S"` "[!] $bail_msg" >>$backup_log
#            mail -s "MySQL backup failed on `hostname` (`hostname -f`)" $mail_contact <$backup_log
#        fi
#    
#        if ! scp -P$archive_port $backup_dir/$my_host-$date_stamp.tar.gz $archive_user@$archive_host:$archive_dir; then
#            bail_msg = "Failed to copy the backup to $archive_host:$archive_dir."
#            echo `date "+%Y-%m-%d %H:%M:%S"` "[!] $bail_msg" 
#            echo `date "+%Y-%m-%d %H:%M:%S"` "[!] $bail_msg" >>$backup_log
#            mail -s "MySQL backup failed on `hostname` (`hostname -f`)" $mail_contact <$backup_log
#        fi
#    
#        if [ $archive_days -gt 0 ]; then
#            logit "Pruning old archives."
#    
#            ssh -p$archive_port $archive_user@$archive_host "find $archive_dir -name '*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'$ext -daystart -mtime +$archive_days -exec rm -rfv {} +" >>$backup_log 2>&1
#        fi
#    else
#        logit "Archiving is disabled."
#    fi
}

bail() {
    echo `date "+%Y-%m-%d %H:%M:%S"` "[!] $1" 
    echo `date "+%Y-%m-%d %H:%M:%S"` "[!] $1" >>$backup_log
    mail -s "MySQL backup failed on `hostname` (`hostname -f`)" $mail_contact <$backup_log
    cleanup
}

######################################################################### 
# "Main" 
######################################################################### 

# Clear log
if [ -f $backup_log ]; then
  cp $backup_log $backup_log.yesterday
fi
echo > $backup_log

if [ $compression -eq 1 ]; then
  # Used during retention code to determine what to delete.
  ext='.tar.gz'
fi

logit "=== Begining Backup. ==="

# Determine / force xtrabackup version
if [ "$xtrabackup_version" == 'auto' ]; then
  logit "* xtrabackup_version set to auto, determining version."
  interimversion=`mysql -V | perl -ne '/Distrib\s+(\d+\.\d+)/; print $1;'`
  logit "** apparently version is $interimversion"
  if [ "$interimversion" == '5.1' ]; then
    xtrabackup_version="xtrabackup_51"
  else 
  	if [ "$interimversion" == '5.5' ]; then
    		xtrabackup_version="xtrabackup_55"
	else
  	    if [ "$interimversion" == '5.6' ]; then
    		xtrabackup_version="xtrabackup_56"
	    else
    	        xtrabackup_version="xtrabackup_57"
            fi
	fi
  fi
  logit "** Version set to $xtrabackup_version"
fi

# Does the backup dir exist?
if [ ! -d $backup_dir ]; then
    bail "$backup_dir is not a directory."
    logit "=== End of Backup ==="
    exit 1
fi

space_free=`/bin/df -k $backup_dir | tail -n 1 | /usr/bin/awk '{print $(NF-2)}' | /bin/grep "[[:digit:]]"`

# How big was yesterday's backup?
logit "$backup_dir/$my_host-$yesterday_date_stamp$ext"
if [ -f "$backup_dir/$my_host-$yesterday_date_stamp$ext" ]; then
  logit "Looking at compressed archive's size"
  yesterday_size=`gzip -l $backup_dir/$my_host-$yesterday_date_stamp$ext | \
    perl -e 'while(<STDIN>){next if /uncompressed/; /(\d+)\s+(\d+)/; printf "%d\n", $2/1024; }'`
  # yesterday_size=`/usr/bin/du -sk $backup_dir/$my_host-$yesterday_date_stamp$ext | /bin/grep -v ^F | /usr/bin/awk '{print $1;}'`
else 
  logit "Checking $backup_dir/$my_host-$yesterday_date_stamp"
  if [ ! -d $backup_dir/$my_host-$yesterday_date_stamp ]; then
      logit "No backup yesterday - $backup_dir/$my_host-$yesterday_date_stamp. Continuing with $space_free KB available."
      yesterday_size="0"
  else
      yesterday_size=`/usr/bin/du -sk $backup_dir/$my_host-$yesterday_date_stamp | /bin/grep -v ^F | /usr/bin/awk '{print $1}'`
  fi
fi


logit "Yesterday's backup took $yesterday_size KB. There is $space_free KB available."

if [ $yesterday_size -gt $space_free ]; then
    bail "$backup_dir is low on space, not continuing."
    logit "=== End of Backup ==="
    exit 1
fi


# If compression is turned on:
#   * remove yesterday's uncompressed backup
#   * set file extension variable for retention logic
if [ $compression -eq 1 ]; then
    logit "Removing yesterday's uncompressed backup: $backup_dir/$my_host-$yesterday_date_stamp"
    rm -rf $backup_dir/$my_host-$yesterday_date_stamp
fi

if [ "$pause_slave" == "true" ]; then
   logit "$0: Pausing Replication for backup."
   if ! mysql -e "stop slave;" >> $backup_log 2>&1; then
       logit "Stopping replication failed -- continuing."
   fi
   mysql -e "show slave status \G;" | grep -i running >> $backup_log 2>&1
fi


# Perform the actual backup
if [ -e $backup_dir/$my_host-$date_stamp ]; then
    mv $backup_dir/$my_host-$date_stamp $backup_dir/$my_host-$date_stamp-$$
    logit "$backup_dir/$my_host-$date_stamp already exists -- saving."
fi
logit "$0: Creating backup."

if [ "$schema_dump" == "true" ]; then
    logit "$0: Getting Schema Dump."
    #
    # Dump Schema with backups to support table restores
    #
    if ! mysqldump --single-transaction -d --skip-lock-tables --all-databases --set-gtid-purged=OFF 1> $backup_dir/$my_host-$date_stamp-schema.dmp 2>> $backup_log ; then
        logit "Schema dump failed -- continuing."
    fi
fi

#
# Current MySQL 5.7 Bug does not support --throttle ( https://bugs.launchpad.net/percona-xtrabackup/+bug/1554235 )
#
if [ ${is_ver_57} > 0 ]; then
    if ! /usr/bin/innobackupex --slave-info --no-timestamp $backup_dir/$my_host-$date_stamp >>$backup_log 2>&1; then
            bail "Backup failed."
            logit "=== End of Backup ==="
            exit 1
    fi
else
    if ! /usr/bin/innobackupex --throttle=${throttle} --slave-info --no-timestamp $backup_dir/$my_host-$date_stamp >>$backup_log 2>&1; then
            bail "Backup failed."
            logit "=== End of Backup ==="
            exit 1
    fi
fi
logit "$0: Preparing backup."
if ! /usr/bin/innobackupex --apply-log $backup_dir/$my_host-$date_stamp >>$backup_log 2>&1; then
    bail "Backup failed while applying logs."
    logit "=== End of Backup ==="
    exit 1
fi

if [ "$pause_slave" == 'true' ]; then
    logit "$0: Starting Replication after backup."
   if ! mysql -e "start slave;" >> $backup_log 2>&1; then
       logit "Starting replication failed -- continuing."
   fi
   mysql -e "show slave status \G;" | grep -i running >> $backup_log 2>&1
fi


# Compress if requested
if [ $compression -eq 1 ]; then
    logit "Compression enabled. Compressing today's backup."
    if ! tar -czf $backup_dir/$my_host-$date_stamp.tar.gz $backup_dir/$my_host-$date_stamp $backup_dir/$my_host-$date_stamp-schema.dmp >>$backup_log 2>&1; then
        bail "Failed to compress backup"
        logit "=== End of Backup ==="
        exit 1
    fi
    chown root:adm $backup_dir/$my_host-$date_stamp.tar.gz

    # Upload to s3, if $s3 is set.
    s3_archive "$my_host-$date_stamp.tar.gz"
fi

cleanup

# Done with backup, restore status to normal operations.  Slave might be 
# delayed.
# TODO: add a while loop to check slave delay is reasonable before exiting 
# and returning to normal operations.

logit "=== End of Backup ==="
