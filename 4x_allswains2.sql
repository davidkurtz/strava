REM 4x_allswains.sql

alter session set statistics_level=ALL;
alter session set nls_date_Format = 'hh24:mi:ss dd.mm.yyyy';
break on activity_gear skip 1 on report
clear computes 
compute avg of sum_dist on activity_gear 
compute avg of sum_dist on report
compute avg of num_pt on activity_gear
compute avg of num_pt on report
compute avg of sum_secs on activity_gear
compute avg of sum_secs on report
compute avg of ele_gain on activity_gear
compute avg of ele_gain on report
compute avg of num_pts on activity_gear
compute avg of num_pts on report
compute count of activity_id on activity_gear
compute count of activity_id on report
Set lines 180 pages 50 timi on serveroutput on
column activity_gear heading 'Activity|Gear' format a10
Column activity_id heading 'Activity|ID' format 9999999999
column geom_id heading 'Geom|ID' format 999
column seq heading '#' format 9
Column activity_name format a15
column time format a20
column lat format 999.99999999
column lng format 999.99999999
column ele format 9999.9
column hr format 999
column sdo_relate format a10
column num_pts heading 'Num|Pts' format 99999
column sum_dist heading 'Dist.|(km)' format 999.999
column sum_secs heading 'Secs' format 9999
column avg_speed heading 'Avg|Speed|(kmph)' format 99.9
column ele_gain heading 'Ele|Gain|(m)' format 9999.9
column ele_loss heading 'Ele|Loss|(m)' format 9999.9
column avg_grade heading 'Avg|Grade|%' format 99.9
column min_ele heading 'Min|Ele|(m)' format 999.9
column max_ele heading 'Max|Ele|(m)' format 999.9
column avg_hr heading 'Avg|HR' format 999
column max_hr heading 'Max|HR' format 999
--DROP TABLE allswains PURGE;
CREATE TABLE allswains
(activity_id NUMBER NOT NULL
,geom_id NUMBER NOT NULL
,seq NUMBER NOT NULL
,min_time DATE
,max_time DATE
,sum_dist NUMBER
,sum_secs NUMBER
,avg_speed NUMBER
,ele_gain NUMBER
,ele_loss NUMBER
,avg_grade NUMBER
,min_ele NUMBER
,max_ele NUMBER
,avg_Hr NUMBER
,max_hr NUMBER
,num_pts NUMBER
);
alter table allswains ADD CONSTRAINT allswains_pk PRIMARY KEY (activity_id, geom_id, seq);
--TRUNCATE TABLE allswains;

BEGIN
  FOR i IN (
    SELECT a.activity_id, g.geom_id
	FROM   activities a, my_geometries g
	WHERE  a.activity_type = 'Ride'
	AND    g.geom_id = 2
--  And    a.activity_date >= TO_DATE('01072019','DDMMYYYY')
    AND    a.xmlns = 'xmlns="http://www.topografix.com/GPX/1/1"'
	AND    SDO_GEOM.RELATE(a.mbr,'anyinteract',g.mbr) = 'TRUE'
--  and    a.activity_name like 'Loop%'
	and not a.activity_id IN(SELECT activity_id FROM allswains)
    ORDER BY a.activity_date DESC
--  FETCH FIRST 10 ROWS ONLY
  ) LOOP

INSERT INTO allswains
(activity_id, geom_id, seq, min_time, max_time, sum_dist, sum_secs, avg_speed, ele_gain, ele_loss, avg_grade, min_ele, max_ele, avg_Hr, max_hr, num_pts)
WITH geo as ( /*route geometry to compare to*/
select /*MATERIALIZE*/ g.*, 25 tol
,      sdo_geom.sdo_length(geom, unit=>'unit=m') geom_length
from   my_geometries g
where  geom_id = i.geom_id /*Swains World Route*/
), a as ( /*extract all points in activity*/
SELECT a.activity_id, g.geom_id, g.geom g_geom, g.tol, g.geom_length
,      EXTRACTVALUE(VALUE(t), 'trkpt/time') time_string
--,      TO_DATE(EXTRACTVALUE(VALUE(t), 'trkpt/time'),'YYYY-MM-DD"T"HH24:MI:SS"Z"') time
,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'trkpt/@lat')) lat
,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'trkpt/@lon')) lng
,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'trkpt/ele')) ele
,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'trkpt/extensions/gpxtpx:TrackPointExtension/gpxtpx:hr'
       ,'xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"'
                   )) hr
FROM   activities a,
       geo g,
       TABLE(XMLSEQUENCE(extract(a.gpx,'/gpx/trk/trkseg/trkpt'
       ,'xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"'
       ))) t
Where  a.activity_type = 'Ride'
And    a.activity_id = i.activity_id
and    SDO_GEOM.RELATE(a.geom,'anyinteract',g.geom,g.tol) = 'TRUE' /*activity has relation to reference geometry*/
), b as ( /*convert time string to date*/
Select a.*
,      CASE 
         WHEN time_string LIKE '____-__-__T__:__:__Z' 
         THEN TO_DATE(time_string,'YYYY-MM-DD"T"HH24:MI:SS"Z"')
         WHEN time_string like '____-__-__T__:__:__+__:__' 
         THEN cast(to_timestamp_tz(time_string,'yyyy-mm-dd"T"hh24:mi:ss"+"TZH:TZM') as date)
       END time
from  a
), c as ( /*smooth elevation*/
Select b.*
,      avg(ele) over (partition by activity_id order by time rows between 2 preceding and 2 following) avg_ele
From   b
), d as ( /*last point*/
Select c.*
,      row_number() over (partition by activity_id order by time) seq
,      lag(time,1) over (partition by activity_id order by time) last_time
,      lag(lat,1) over (partition by activity_id order by time) last_lat
,      lag(lng,1) over (partition by activity_id order by time) last_lng
--,      lag(ele,1) over (partition by activity_id order by time) last_ele
,      lag(avg_ele,1) over (partition by activity_id order by time) last_avg_ele
From   c
), e as ( /*make points*/
SELECT d.* 
,      strava_pkg.make_point(lng,lat) loc
,      strava_pkg.make_point(last_lng,last_lat) last_loc
FROM   d
), f as ( /*determine whether point is inside the polygon*/
select e.*
,      86400*(time-last_time) secs
,      avg_ele-last_avg_ele ele_diff
,      sdo_geom.sdo_distance(loc,last_loc,0.05,'unit=m') dist
,      SDO_GEOM.RELATE(loc,'anyinteract', g_geom, tol) sdo_relate
FROM   e
), g as (
select f.*
,      CASE WHEN sdo_relate != lag(sdo_relate,1) over (partition by activity_id order by time) THEN 1 END sdo_diff
from   f
), h as (
select g.*
,      SUM(sdo_diff) over (partition by activity_id order by time range between unbounded preceding and current row) sdo_seq
from g
where  sdo_relate = 'TRUE'
)
select activity_id, geom_id, sdo_seq
, min(time) min_time, max(time) max_time
, sum(dist)/1000 sum_dist
, sum(secs) sum_secs
, 3.6*sum(dist)/sum(secs) avg_speed
, sum(greatest(0,ele_diff)) ele_gain
, sum(least(0,ele_diff)) ele_loss
, 100*sum(ele_diff*dist)/sum(dist*dist) avg_grade
, min(ele) min_ele
, max(ele) max_ele
, sum(hr*secs)/sum(secs) avg_Hr
, max(hr) max_hr
, count(*) num_pts
from   h
group by activity_id, geom_id, sdo_seq, geom_length
having sum(dist)>= geom_length/2 /*make sure line we find is longer than half route to prevent fragmentation*/;

  dbms_output.put_line(i.activity_id||':'||SQL%rowcount||' rows inserted');
  commit;

  END LOOP;
END;
/

--spool 4x_allswains_plan
--select * from table(dbms_xplan.display_cursor(null,null,'ADVANCED +IOSTATS -PROJECTION +ADAPTIVE'));
spool 4x_allswains
select a.activity_gear, count(distinct s.activity_id) num_acts
, count(*) num_swains, avg(sum_dist) avg_dist, avg(sum_secs) avg_secs
, min(a.activity_date), max(a.activity_date), max(sum_secs)
from allswains s, activities a
where s.activity_id = a.activity_id
and sum_secs <= 300
--And    a.activity_date >= TO_DATE('01072019','DDMMYYYY')
group by a.activity_Gear
order by avg_secs
/
select a.activity_gear, s.*
from allswains s, activities a
where s.activity_id = a.activity_id
and s.geom_id = 2
--And    a.activity_date >= TO_DATE('01072019','DDMMYYYY')
order by activity_gear, min_time
/
spool off

/*
select sql_id, count(*) ash_Secs
from v$active_Session_history
where sql_id IS NOT NULL
group by sql_id
order by ash_secs desc
fetch first 3 rows only
/

set pages 99 lines 180
select * from table(dbms_xplan.display_cursor('45d6nkzs1b8tp',null,'ADVANCED +IOSTATS -PROJECTION +ADAPTIVE'));
select * from table(dbms_xplan.display_cursor('629tp8hfyyuw1',null,'ADVANCED +IOSTATS -PROJECTION +ADAPTIVE'));
*/