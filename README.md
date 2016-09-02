
Documentation about how to use the automated mysql installer
====

About user.template
----

The user.template file contains placeholder data.  When checking out this repo on a target system, ensure that you edit it to contain the real passwords for the system, and DO NOT check in the file.  

The following users are handled:

- root:     MySQL admin login
- slave:    MySQL replication login
- dba:   moz dba login

The [type].user.template file(s) contains placeholder data specifically for custom databases.  When checking out this repo on a target system, ensure that you edit it to contain the real passwords for the system, and DO NOT check in the file.  

- status: status\_user (used for gathering stats)

Capistrano mysql installations
----

The main cap file for automating mysql installs & updates in parallel is Capfile.

It in turn loads additional ruby cap file from the lib directory
- servers.rb ( roles and servers )
- mysql.rb (various runnables tasks)

By default, we will install percona's distribution of mysql 5.7
- to install a different version, pass in -s mysql\_version=<X.Y> on the cap command line

The cap setup assumes the following:

- latest version of capistrano and associated dependencies are installed locally
- latest copy of this repo is available locally ( git clone phil-hildebrand/cap-mysql )
- the user running the deploys can ssh without passwords to all servers being deployed to
 - if keys have pass phrases, use the agent cache with an added key
 -  % exec ssh-agent bash
 -  % ssh-add ~/.ssh/my-user-key
- that the user has determined every server listed for mysql installation does in fact need it installed
 - IE: there is no 'rollback' per say.  It will back a backup of any data existing in /data, but does not
 -  do any kind of transactional consistency with respect to that backup, nor does it currently shut down
 -  any exiting mysql instance.

Supporting files 
----
- lib directory
-- server.rb server role definitions
-- mysql.rb various tasks for mysql installations

Installing MySQL with cap
----

- copy git cap\_mysql respository locally
- copy setup/*user.template files into home directory ( `${gitub cloned path}/cap_mysql` )
- edit *user.template files to contain correct passwords
- edit Capfile to contain correct location of {repo_dir}
- Run cap with appropriate options:
 - cap -vT // returns available tasks
 - cap --dry-run [task] // to see what will be run
 - cap install_percona_mysql HOSTS=a,b,...,z  // to install mysql concurrently on hosts a,b,...,z

Note: cap installation will install and configure mysql, backups, and heartbeat.  It does not curently,
       however, setup master - master replication.

```
Usage: cap [--dry-run] <task> [-s options]  <HOSTS|ROLES=hostname|role> \ 
      -s varfile ( Default=/tmp/mysql_cap_variables) \ 
      -s local_repo ( Default=.) \ 
      -s mysql_version ( [5.5|5.6|5.7] Default=5.7 ) \ 
      -s mysql_type ( [prod|stage|test] Default=prod ) \ 
      -s mysql_master ( Default=none ex: node_1 ) \ 
      -s ssd ( Default=true )
      -s scheduler ( [noop|deadline|cfq] Default=noop )
      -s mem ( in GB - Default=auto - ex: mem=10 )
      -s backup ( [true|false] Default=true - enables backups on node )

Example: cap --dry-run run_custom -s mysql_type=prod -s mysql_version=5.7
```
