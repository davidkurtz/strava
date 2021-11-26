REM strava_pkg_test.sql
set timi on serveroutput on pages 99 lines 180 long 500
--@@strava_pkg

select activity_id, activity_date, activity_name, distance_km
from activities
where activity_Date > TO_DATE('01.12.20','DD.MM.YY');

rollback;
set serveroutput on timi on
--exec strava_pkg.activity_area_hsearch(4516029899);

--process unmatched activities
set pages 99 lines 180 timi on serveroutput on
column activity_name format a60
BEGIN 
  FOR i IN (
select a.activity_id, activity_date, activity_name
, distance_km, num_pts, round(num_pts/nullif(distance_km,0),0) ppkm
from activities a
where activity_id NOT IN (select distinct activity_id from activity_areas)
and num_pts>0
--and activity_id NOT IN (2331601146)
order by 
num_pts
--activity_Date 
--distance_km
desc
--fetch first 10 rows only
  ) LOOP
    strava_pkg.activity_area_hsearch(i.activity_id);
    commit;
  END LOOP;
END;
/

insert into activity_areas values (2331601146,'SOV',1159320701,NULL);
insert into activity_areas values (2331601146,'GEOU',1159320743,NULL);

--summary of matched activities
select count(distinct activity_id)
, count(distinct area_code||area_numbeR)
, count(*)
from activity_areas
/

--points for activity
select activity_id
, SDO_UTIL.GETNUMVERTICES(geom) num_vert_4326
, SDO_UTIL.GETNUMVERTICES(geom_27700) num_vert_27700
from activities
where activity_id = 2331601146
/

--areas with children, but none of children identified
select b1.activity_id, b1.area_code, b1.area_number, a1.name, a1.num_children
from my_areas a1, activity_areas b1
where a1.area_code = b1.area_code
and a1.area_number = b1.area_number
and a1.num_children > 0
and not exists(
  select 'x'
  from my_areas a2, activity_areas b2
  where a2.area_code = b2.area_code
  and a2.area_number = b2.area_number
  and b2.activity_id = b1.activity_id
  and a2.parent_area_code = a1.area_code
  and a2.parent_area_number = a1.area_number)
/

--activities with >10000 pts and >100 pts/km
with x as (
select a.activity_id, activity_name
, distance_km, num_pts
, sdo_util.getnumvertices(sdo_util.simplify(geom,1)) simp_pts
from activities a
)
select x.*
, round(num_pts/NULLIF(distance_km,0)) ppkm
, round(simp_pts/NULLIF(distance_km,0)) sppkm
from x
where num_pts > 10000
and num_pts>100*distance_km
order by num_pts
/

--a test area
select a.activity_id, a.activity_date, a.activity_name, a.distance_km
from activities a
where activity_id = 2402083398


--full hierarchy of areas
column path format a100
column name format a40
select level, m.area_code, m.area_number
, LPAD('.',level-1,'.')||m.name name
--, m.parent_area_code, m.parent_area_number
, sys_connect_by_path(replace(area_code||':'||name,'/','~'),'/') path
from my_areas m
where  area_level <= 4
start with m.parent_area_code is null and m.parent_area_number is null
connect by prior m.area_code = m.parent_area_code and prior m.area_number = m.parent_area_number
order by path;

--report hierarchy for an area
column name format a50
with m as (
select a.area_code, a.area_number, a.geom_length, m.name, m.parent_area_code, m.parent_area_number
from activity_areas a, my_areas m
where a.activity_id = 2402083398
and m.area_code = a.area_code
and m.area_number = a.area_number
)
select m.area_code, m.area_number, LPAD('.',level,'.')||m.name name, m.geom_length
--, m.parent_area_code, m.parent_area_number
from m
start with m.parent_area_code is null and m.parent_area_number is null
connect by prior m.area_code = m.parent_area_code 
and prior m.area_number = m.parent_area_number
/

--NL activities
select activity_id
from activity_areas
where area_code = 'SOV' and area_number = 1159321093
/

--activities by root areas
select m.name, count(*)
from activity_areas aa, my_areas m
where m.area_code = aa.area_code
and m.area_number = aa.area_number
and m.parent_area_code IS NULL
and m.parent_area_number IS NULL
group by m.name
/

select a.area_code, a.area_number, m.name, count(*) num_acts
from activity_areas a, my_areas m
where a.area_code = m.area_code
and a.area_number = m.area_number
group by a.area_code, a.area_number, m.name
order by num_acts desc
fetch first 20 rows only
/

drop table my_areas_backup purge;
create table my_areas_backup as 
SELECT area_code, area_number, uqid, name, parent_area_code, parent_area_number, parent_uqid
FROM   my_areas AS OF TIMESTAMP TO_TIMESTAMP('2021-03-13 10:00:00', 'YYYY-MM-DD HH24:MI:SS');

create unique index my_areas_backup on my_areas_backup (area_code, area_number);

select m1.area_code, m1.area_number, m1.uqid, m1.name
, m1.parent_area_code, m1.parent_area_number, m1.parent_uqid
from my_areas m1
where m1.area_code = m1.parent_area_code
and m1.area_number = m1.parent_area_number
/
