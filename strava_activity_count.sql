REM strava_activity_count.sql
set pages 99 lines 140
column name format a30
column area_code heading 'Area|Code' format a4
column area_number heading 'Area Number' format 9999999999
column country_areas heading 'Country|Areas' format 99999
column matchable_country_areas heading 'Matchable|Areas' format 99999
column visited_areas heading 'Visited|Areas' format 99999
column visited_matchable_areas heading 'Visited|Matchable' format 99999
column num_activities heading 'Number of|Activities' format 9999
column geom_length heading 'Geom|Length' format 999999
column country format a40
column types format a10
clear screen
spool strava_activity_count.lst
with m (root_area_code, root_area_number, root_name, area_code, area_number, name, matchable, my_level) as (
select connect_by_root area_code
, connect_by_root area_number
, connect_by_root name
, area_code, area_number, name
, matchable, level
from my_areas m
START WITH parent_area_code is null and parent_area_number IS NULL
CONNECT BY NOCYCLE prior m.area_code   = m.parent_area_code
               AND prior m.area_number = m.parent_area_number
), a as (
select aa.area_code, aa.area_number, aa.activity_id, a.type, aa.geom_length
from activity_areas aa
  inner join activities a on a.activity_id = aa.activity_id 
    --AND type = 'Ride'
    --AND type IN('Walk','Hike')
    --AND type = 'NordicSki'
    AND NOT type IN('VirtualRide')
--where a.start_date_local >= TRUNC(SYSDATE,'YYYY')
)
select root_name country
, count(distinct m.area_code||m.area_number) country_areas
, count(distinct a.area_code||a.area_number) visited_areas
, count(distinct CASE WHEN matchable=1 THEN m.area_code||m.area_number END) matchable_country_areas
, count(distinct CASE WHEN matchable=1 THEN a.area_code||a.area_number END) visited_matchable_areas
, count(distinct a.activity_id) num_activities
, sum(CASE WHEN my_level = 1 THEN a.geom_length END) geom_length
, listagg(DISTINCT a.type,' ,') within group (order by type) types
from m
  left outer join a on m.area_code = a.area_code and m.area_number = a.area_number
--where m.matchable = 1
group by root_area_code, root_area_number, root_name
having count(a.activity_id)>0
order by geom_length desc
/
spool off

