REM 1a_create_strava_user.sql
spool 1a_create_strava_user
connect / as sysdba
create user strava identified by strava;
grant connect, resource to strava;
grant create view to strava;
grant select_catalog_role to strava;
grant XDBADMIN to STRAVA;
grant alter session to STRAVA;
alter user strava quota unlimited on users;
alter user strava default tablespace users;

GRANT CREATE ANY DIRECTORY TO strava;
CREATE OR REPLACE DIRECTORY strava as '/tmp/strava';
CREATE OR REPLACE DIRECTORY activities as '/tmp/strava/activities';
CREATE OR REPLACE DIRECTORY exec_dir AS '/usr/bin';

GRANT READ, EXECUTE ON DIRECTORY exec_dir TO strava;
GRANT READ, EXECUTE ON DIRECTORY strava TO strava;
GRANT READ ON DIRECTORY activities TO strava;
spool off
