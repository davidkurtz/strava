REM job_renew_strava_tokens.sql
clear screen
column client_id format a10
column client_secret format a40
column access_token format a40
column refresh_token format a40
column owner format a8
column user_name format a8
column job_creator format a8
column job_name format a30
column job_subname format a30
column job_action format a40
column repeat_interval format a40
column job_class format a20
column operation format a10
column status format a10
column raise_Events format a30
column client_id format a16
column program_owner format a8
column program_name format a30
column source format a30
column connect_credential_owner format a8
column connect_credential_name format a30
column credential_owner format a8
column credential_name format a30
column schedule_owner format a8
column schedule_name format a30
column event_queue_owner format a8
column event_queue_name format a30
column event_queue_agent format a30
column event_condition format a30
column event_rule format a30
column destination_owner format a8
column destination format a30
column file_watcher_owner format a8
column file_watcher_name format a30
column session_id format a16
set pages 999 lines 120

--@@strava_http.sql

spool renew_strava_tokens.lst

ALTER SESSION SET TIME_ZONE = 'UTC';

set serveroutput on 
--force renew
EXEC strava.strava_http.renew_strava_tokens(p_force=>TRUE);

--REM create job
--EXEC dbms_Scheduler.drop_job(job_name => 'STRAVA.RENEW_STRAVA_TOKENS_JOB');
BEGIN
  dbms_Scheduler.create_job
  (job_name => 'STRAVA.RENEW_STRAVA_TOKENS_JOB'
  ,job_type => 'STORED_PROCEDURE'
  ,job_action => 'STRAVA.STRAVA_HTTP.RENEW_STRAVA_TOKENS'
  ,job_class => 'SYS.HIGH' --because it is important to renew the token
  ,repeat_interval => 'FREQ=HOURLY;INTERVAL=6'
  ,enabled => TRUE
  ,auto_drop => FALSE
  );
END ;
/
--EXEC dbms_scheduler.run_job(job_name => 'STRAVA.RENEW_STRAVA_TOKENS_JOB');

select * fROM strava_tokens
/

select * from dba_scheduler_jobs 
where owner = 'STRAVA' --AND job_name = 'RENEW_STRAVA_TOKENS_JOB'
ORDER BY 1,2
/

select * from dba_scheduler_job_log 
where owner = 'STRAVA' --AND job_name = 'RENEW_STRAVA_TOKENS_JOB'
ORDER BY 1 desc,2 FETCH FIRST 5 ROWS ONLY
/
select * from dba_scheduler_job_run_details
where owner = 'STRAVA' --AND job_name = 'RENEW_STRAVA_TOKENS_JOB'
ORDER BY 1 desc,2 FETCH FIRST 5 ROWS ONLY
/

spool off

