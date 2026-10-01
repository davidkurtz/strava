set pages 999 lines 120
column plan_id format 999999
column plan format a10
column sub_plan format a8
column cpu_method format a12
column mgmt_method format a12
column queueing_mth format a12
column CPU_P1 heading 'CPU|P1' format 999
column ACTIVE_SESS_POOL_MTH format a30
column PARALLEL_DEGREE_LIMIT_MTH format a30
column status format a12
column mandatory format a12
column comments format a20
column group_or_subplan heading 'GROUP OR|SUBPLAN' format a12
column PARALLEL_SERVER_LIMIT heading 'PARALLEL|SERVER|LIMIT' format a8
column MAX_UTILIZATION_LIMIT heading 'MAX|UTILIZATION|LIMIT' format a12
column UTILIZATION_LIMIT heading 'UTILIZATION|LIMIT' format a12
column PARALLEL_TARGET_PERCENTAGE  heading 'PARALLEL|TARGET %' format a12
column PARALLEL_DEGREE_LIMIT_P1 heading 'PARALLEL|DEGREE|LIMIT_P1' format a8
clear screen
spool rsrc_plans.lst
show parameters resource_manager
set lines 100
select * from dba_rsrc_plans
where plan = 'OLTP_PLAN';
select plan, group_or_subplan, type, cpu_p1, parallel_target_percentage
, parallel_degree_limit_p1, max_utilization_limit, parallel_server_limit, utilization_limit
from dba_rsrc_plan_directives 
where plan = 'OLTP_PLAN'
order by cpu_p1 desc
;
select * from dba_rsrc_plan_directives ;
spool off