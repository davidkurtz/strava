REM strava_privs.sql

connect / as sysdba
create user strava identified by strava;
GRANT connect, resource TO strava;
GRANT create view TO strava;
GRANT select_catalog_role TO strava;
GRANT XDBADMIN to STRAVA;
GRANT alter session to STRAVA;
GRANT CREATE SYNONYM to STRAVA;

ALTER USER strava quota unlimited on users;
ALTER USER strava default tablespace users;

GRANT CREATE ANY DIRECTORY TO strava;
CREATE OR REPLACE DIRECTORY strava as '/tmp/strava';
CREATE OR REPLACE DIRECTORY activities as '/tmp/strava/activities';
CREATE OR REPLACE DIRECTORY exec_dir AS '/usr/bin';

GRANT READ, EXECUTE ON DIRECTORY exec_dir TO strava;
GRANT READ, EXECUTE ON DIRECTORY strava TO strava;
GRANT READ ON DIRECTORY activities TO strava;
