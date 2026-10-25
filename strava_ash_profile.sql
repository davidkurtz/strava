REM strava_ash_profile.sql
set pages 999 lines 200
column module format a14
column action format a32
column event format a30 
column consumer_group heading 'Consumer|Group' format a12
column ash_secs heading 'ASH|Secs' format 999,999
clear screen
spool strava_ash_profile.lst
with h as (
select module, usecs_per_row, consumer_group_id
, NVL(event,'CPU + CPU Wait') event
, case when module = 'DBMS_SCHEDULER' --AND (action like '%ACTIVITY%JOB%'  OR action like 'POSTUPG$OMLCORE%')
       THEN regexp_substr(action,'[^[0-9]]+',1,1) 
       ELSE regexp_substr(action,'[^:]+',1,1) 
  END action
from dba_hist_active_sess_history
--from gv$active_session_History
--where not module IN('T2','MMON_SLAVE','SYS_AUTO_STS_MODULE','sys$bsg_timeout')
--and not module like 'dbms_stats%'
where module like 'STRAVA%' 
OR (module = 'DBMS_SCHEDULER'
and not (action like 'ORA$%' 
      or action like 'UTL%'
      or action in ('DB_MONITOR_SQL_LOGSTASHJOB_ALT','CHECK_ODI_SCHEDULES','ELASTIC_POOL_CACHE_JOB','CLEANUP_ONLINE_IND_BUILD'
   ,'CLEANUP_TOBE_DROPPED_IDX','CHECK_ODI_SCHEDULES','PURGE_LOG','PDBCS_CACHE_JOB','DATA_SHARE_INDEX_INCR_JOB'
   )))
--and sample_time >= sysdate-7
)
select h.module, h.action, h.event, cg.consumer_group, sum(usecs_per_Row)/1e6 ash_Secs
from h
  left outer join dba_rsrc_consumer_groups cg on cg.consumer_group_id = h.consumer_group_id
group by h.module, h.action, h.event, cg.consumer_group
order by ash_secs desc
--fetch first 20 rows only
/
spool off
