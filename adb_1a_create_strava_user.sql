REM adb_1a_create_strava_user.sql
spool asb_1a_create_strava_user

purge dba_recyclebin;
select * from dba_recyclebin;

create user strava identified by HairyCyc1ist;
grant connect, resource to strava;
grant create view to strava;
grant select_catalog_role to strava;
grant create job to strava;
--grant XDBADMIN to STRAVA;
--grant alter session to STRAVA;
alter user strava quota unlimited on users;
alter user strava default tablespace users;

GRANT CREATE ANY DIRECTORY TO strava;
--CREATE OR REPLACE DIRECTORY strava as '/tmp/strava';
--CREATE OR REPLACE DIRECTORY activities as '/tmp/strava/activities';
--CREATE OR REPLACE DIRECTORY exec_dir AS '/usr/bin';
DROP DIRECTORY strava;
DROP DIRECTORY activities;
DROP DIRECTORY exec_dir;

--GRANT READ, EXECUTE ON DIRECTORY exec_dir TO strava;
--GRANT READ, EXECUTE ON DIRECTORY strava TO strava;
--GRANT READ ON DIRECTORY activities TO strava;

GRANT EXECUTE ON sys.dbms_crypto TO strava;

spool off

