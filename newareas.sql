REM newareas.sql
set pages 99 lines 200 trimspool on
break on activity_date on activity_id on activity_type on activity_name on report
column activity_type format a12
column activity_name format a50
column name_hierarchy format a90
column geom_length heading 'Geom|Len' format 999.9
compute sum of geom_length on activity_id
compute sum of geom_length on report
spool newareas
with x as (
select a.activity_id, a.activity_type, a.activity_date, a.activity_name
, ma.area_code, ma.area_number
--, ma.name, ma.name_hierarchy
, aa.geom_length
, row_number() over (partition by aa.area_code, aa.area_number ORDER BY a.activity_date) seq
from activities a
, activity_areas aa
, my_areas ma
where a.activity_id = aa.activity_id
and ma.area_code = aa.area_code
and ma.area_number = aa.area_number
and a.activity_type = 'Ride' --'Nordic Ski'
and ma.nuM_children IS NULL
)
select x.activity_id, x.activity_type, x.activity_date, x.activity_name
, geom_length
, strava_pkg.name_hierarchy_fn(x.area_code, x.area_number) name_hierarchy
from x
where seq = 1
and activity_date > ADD_MONTHS(sysdate,-12)
order by x.activity_date, x.activity_id, x.geom_length DESC nulls last
--fetch first 10 rows only
/
spool off
