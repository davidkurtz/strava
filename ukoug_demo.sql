REM ukoug_demo.sql
clear screen columns
set pages 999 lines 148 long 560 echo on
alter session set nls_Date_format = 'dd/mm/rr hh24:mi:ss';
alter session set nls_timestamp_format = 'dd/mm/rr HH24.MI.SSXFF';
alter session set nls_timestamp_tz_format = 'dd/mm/rr HH24.MI.SSXFF TZh:tzm';
column activity_id format 999999999999
column area_list format a148
column aspect_type heading 'Aspect|Type' format a7
column enabled format a7
column description format a148
column event_timestamp format a32
column failure_count heading 'Failure|Count' format 99999
column gear_id format a9
column gear_name format a18
column http_status heading 'HTTP|Status' format 9999
column id format 9999
column job_action format a50
column job_Class format a37
column job_name format a36
column job_priority heading 'Job|Priority' format 9999
column last_start_date format a32
column last_run_duration format a30
column last_updated format a32
column log_date format a34
column log_id format 99999999
column long_all_usage heading 'Long|All|Usage' format 9999
column long_read_usage heading 'Long|Read|Usage' format 9999
column name format a60
column next_run_date format a32
column number_of_arguments heading 'Number of|Arguments' format 999
column object_id format 99999999999
column object_type heading 'Object|Type' format a10
column owner format a8
column owner_id format 99999999
column payload format a100
column private format 99
column processing_status heading 'Process|Status' format 999
column received_at format a32
column repeat_interval format a56
column req_type heading 'Req|Type' format a4
column request_time format a25
column run_count heading 'Run|Count' format 99999
column run_duration format a19
column schedule_type heading 'Schedule|Type' format a9
column short_all_usage heading 'Short|All|Usage' format 9999
column short_read_usage heading 'Short|Read|Usage' format 9999
column start_date format a32
column start_date_local format a27
column start_date_utc format a27
column state format a10
column status format a10
column status_msg format a70
column subscription_id heading 'Subscription|ID' format 9999999
column type format a11
column updates format a50
column url format a78
column versions_endscn heading 'Version|End SCN' format 99999999999999
column versions_endtime heading 'Version|End Time' format a28
column versions_startscn heading 'Version|Start SCN' format 99999999999999
column versions_starttime heading 'Version|Start Time' format a28
column versions_operation heading 'Version|Operation' format a9
column versions_xid heading 'Version|Transaction ID' format a16
column visibility format a14
clear screen
spool ukoug_demo
accept hours number default 1 prompt "Hours? "
select * from webhook_events where received_at >= sysdate-&&hours/24 
order by received_at desc fetch first 4 rows only;
pause

select * from api_log where request_time >= sysdate-&&hours/24 
order by request_time desc fetch first 10 rows only;
pause

select activity_id, start_date_local, name, type, processing_status, area_list, description
from activities where last_updated >= sysdate-&&hours/24 
order by start_date_local desc fetch first 4 rows only;
pause

select versions_startscn, versions_starttime, 
       versions_endscn, versions_endtime,
       versions_xid, versions_operation,
       --a.*
       activity_id, start_date_utc, start_date_local, name, type, gear_id, gear_name, private, visibility, last_updated, processing_status
	   , area_list, description
from activities a VERSIONS BETWEEN TIMESTAMP systimestamp - INTERVAL '&&hours' HOUR AND systimestamp
where versions_operation IS NOT NULL
order by start_date_utc desc, versions_startscn desc fetch first 4 rows only;
pause

select owner, job_name, job_type, job_action, number_of_arguments, schedule_type, start_date, repeat_interval, job_class
,enabled, state, job_priority, run_count, failure_count, last_start_date, last_run_duration, next_run_date
from all_scheduler_jobs where owner = 'STRAVA' and last_start_date >= sysdate-&&hours/24 
order by last_start_date desc fetch first 8 rows only;
pause

select log_id, log_date, job_name, job_class, status --, additional_info
from all_scheduler_job_log where log_date >= sysdate-&&hours/24 
order by 2 desc fetch first 20 rows only;
pause
set long 50000
select log_id, log_date, job_name, status, error#, run_duration, output
from all_scheduler_job_run_details where log_date >= sysdate-&&hours/24 
order by 2 desc fetch first 5 rows only;
pause
spool off
