-- Status user grants

drop user if exists status@localhost;
create user if not exists status@localhost identified by '' with MAX_USER_CONNECTIONS 20;
alter user if exists status@localhost identified by '' with MAX_USER_CONNECTIONS 20;
grant replication client on *.* to status@localhost;

-- Replication user grants

drop user if  exists slave@localhost;
create user if not exists slave@localhost identified by 'slave_pass'  with  MAX_USER_CONNECTIONS 20; 
alter user if exists slave@localhost identified by 'slave_pass'  with  MAX_USER_CONNECTIONS 20; 
drop user if  exists slave@'my_host';
create user if not exists slave@'my_host' identified by 'slave_pass'  with  MAX_USER_CONNECTIONS 20; 
alter user if exists slave@'my_host' identified by 'slave_pass'  with  MAX_USER_CONNECTIONS 20; 
drop user if  exists slave@'%';
create user if not exists slave@'%' identified by 'slave_pass'  with  MAX_USER_CONNECTIONS 20; 
alter user if exists slave@'%' identified by 'slave_pass'  with  MAX_USER_CONNECTIONS 20; 
grant super, replication client, replication slave, reload  on *.* to slave@localhost;
grant super, replication client, replication slave, reload  on *.* to slave@'my_host';
grant super, replication client, replication slave, reload  on *.* to slave@'%';

-- DBA user grants

drop user if  exists dba@localhost;
create user if not exists dba@localhost identified by 'dba_pass'  with  MAX_USER_CONNECTIONS 20; 
alter user if exists dba@localhost identified by 'dba_pass'  with  MAX_USER_CONNECTIONS 20; 
drop user if  exists dba@'my_host';
create user if not exists dba@'my_host' identified by 'dba_pass'  with  MAX_USER_CONNECTIONS 20; 
alter user if exists dba@'my_host' identified by 'dba_pass'  with  MAX_USER_CONNECTIONS 20; 
drop user if  exists dba@'%';
create user if not exists dba@'%' identified by 'dba_pass'  with  MAX_USER_CONNECTIONS 20; 
alter user if exists dba@'%' identified by 'dba_pass'  with  MAX_USER_CONNECTIONS 20; 
grant all on *.* to dba@'localhost';
grant all on *.* to dba@'my_host';
grant all on *.* to dba@'%';
