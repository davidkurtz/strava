REM 4b_allswains.sql

alter session set statistics_level=ALL;
alter session set nls_date_Format = 'hh24:mi:ss dd.mm.yyyy';
break on activity_id skip 1
compute sum of sum_dist on activity_id
compute sum of num_pt on activity_id
compute sum of sum_secs on activity_id
Set lines 180 pages 50 timi on
Column activity_id heading 'Activity|ID'
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
DROP TABLE allswains PURGE;
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
TRUNCATE TABLE allswains;

BEGIN
  FOR i IN (
    SELECT a.activity_id, g.geom_id
	FROM   activities a, my_geometries g
	WHERE  a.activity_type = 'Ride'
	AND    g.geom_id = 2
	AND    SDO_GEOM.RELATE(a.mbr,'anyinteract',g.mbr) = 'TRUE'
--	AND rownum <= 30
	MINUS SELECT activity_id, geom_id FROM allswains
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
), b as ( /*smooth elevation*/
Select a.*
,      CASE 
         WHEN time_string LIKE '____-__-__T__:__:__Z' 
         THEN TO_DATE(time_string,'YYYY-MM-DD"T"HH24:MI:SS"Z"')
         WHEN time_string like '____-__-__T__:__:__+__:__' 
         THEN cast(to_timestamp_tz(time_string,'yyyy-mm-dd"T"hh24:mi:ss"+"TZH:TZM') as date)
       END time
,      avg(ele) over (partition by activity_id order by time rows between 2 preceding and 2 following) avg_ele
From   a
), c as ( /*last point*/
Select b.*
,      row_number() over (partition by activity_id order by time) seq
,      lag(time,1) over (partition by activity_id order by time) last_time
,      lag(lat,1) over (partition by activity_id order by time) last_lat
,      lag(lng,1) over (partition by activity_id order by time) last_lng
--,      lag(ele,1) over (partition by activity_id order by time) last_ele
,      lag(avg_ele,1) over (partition by activity_id order by time) last_avg_ele
From   b
), d as ( /*make points*/
SELECT c.* 
,      strava_pkg.make_point(lng,lat) loc
,      strava_pkg.make_point(last_lng,last_lat) last_loc
FROM   c
), e as ( /*determine whether point is inside the polygon*/
select d.*
,      86400*(time-last_time) secs
,      avg_ele-last_avg_ele ele_diff
,      sdo_geom.sdo_distance(loc,last_loc,0.05,'unit=m') dist
,      SDO_GEOM.RELATE(loc,'anyinteract', g_geom, tol) sdo_relate
FROM   d
), f as (
select e.*
,      CASE WHEN sdo_relate != lag(sdo_relate,1) over (partition by activity_id order by time) THEN 1 END sdo_diff
from   e
), g as (
select f.*
,      SUM(sdo_diff) over (partition by activity_id order by time range between unbounded preceding and current row) sdo_seq
from f
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
from   g
group by activity_id, geom_id, sdo_seq, g.geom_length
having sum(dist)>= g.geom_length/2 /*make sure line we find is longer than half route to prevent fragmentation*/;
    commit;
  END LOOP;
END;
/

spool 4b_allswains_plan
select * from table(dbms_xplan.display_cursor(null,null,'ADVANCED +IOSTATS -PROJECTION +ADAPTIVE'))
/
spool 4b_allswains
select count(distinct activity_id), count(*)
from allswains
/
select * from allswains 
order by min_time
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