-- Status user grants

grant replication client on *.* to status@localhost  with  MAX_USER_CONNECTIONS 20; 

-- Replication user grants

grant super, replication client, replication slave, reload  on *.* to slave@localhost identified by 'slave_pass'  with  MAX_USER_CONNECTIONS 20; 
grant super, replication client, replication slave, reload  on *.* to slave@'my_host' identified by 'slave_pass'  with  MAX_USER_CONNECTIONS 20; 
grant super, replication client, replication slave, reload  on *.* to slave@'%' identified by 'slave_pass'  with  MAX_USER_CONNECTIONS 20; 

-- DBA user grants

grant all on *.* to dba@'%' identified by 'dba_pass'  with  MAX_USER_CONNECTIONS 20; 
grant all on *.* to dba@'localhost' identified by 'dba_pass'  with  MAX_USER_CONNECTIONS 20; 
grant all on *.* to dba@'my_host' identified by 'dba_pass'  with  MAX_USER_CONNECTIONS 20; 
