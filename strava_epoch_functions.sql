REM strava_epoch_functions.sql
clear screen 
set echo on
spool strava_epoch_functions.lst

CREATE OR REPLACE FUNCTION strava.epoch_to_tstz 
(p_epoch_seconds IN NUMBER
) RETURN TIMESTAMP DETERMINISTIC IS
BEGIN
  RETURN TO_TIMESTAMP_TZ('1970-01-01 00:00:00 UTC',  'YYYY-MM-DD HH24:MI:SS TZR') 
       + NUMTODSINTERVAL(p_epoch_seconds, 'SECOND');
END epoch_to_tstz;
/
show errors

CREATE OR REPLACE FUNCTION strava.tstz_to_epoch 
(p_tstz IN TIMESTAMP WITH TIME ZONE
) RETURN NUMBER DETERMINISTIC IS
  k_epoch_tz CONSTANT TIMESTAMP := TO_TIMESTAMP_TZ('1970-01-01 00:00:00 UTC',  'YYYY-MM-DD HH24:MI:SS TZR');
BEGIN
  RETURN EXTRACT(DAY FROM (p_tstz - k_epoch_tz)) * 86400
       + EXTRACT(HOUR FROM (p_tstz - k_epoch_tz)) * 3600
       + EXTRACT(MINUTE FROM (p_tstz - k_epoch_tz)) * 60 
       + EXTRACT(SECOND FROM (p_tstz - k_epoch_tz));
END tstz_to_epoch;
/
show errors

select tstz_to_epoch(sysdate) from dual;
select epoch_to_tstz(1770392934.123456) from dual;
select epoch_to_tstz(1769615905) from dual;

spool off