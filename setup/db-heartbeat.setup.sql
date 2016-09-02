-- SQL to set up the mk-heartbeat stuff 
-- RUN ME ON THE MASTER, AFTER REPLICATION IS SET UP

BEGIN;

CREATE DATABASE IF NOT EXISTS heartbeat;
USE heartbeat;

GRANT SELECT,INSERT,UPDATE,DELETE
  ON heartbeat.*
  TO 'heartbeat'@'%' 
  IDENTIFIED BY 'heartbeat';

GRANT SUPER, REPLICATION CLIENT
  ON *.*
  TO 'heartbeat'@'%' 
  IDENTIFIED BY 'heartbeat';

COMMIT;
