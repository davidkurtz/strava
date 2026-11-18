REM climbing_stats.sql
with a as (
select trunc(start_date_local,'mm') start_date_local
, count(*) num_activities
, sum(elapsed_time) elapsed_time
, sum(moving_time) moving_time
, sum(distance_km) distance_km
, sum(elevation_gain) elevation_gain
, max(elevation_high) elevation_high
, min(elevation_low) elevation_low
from activities
where start_date_local >= TO_DATE('01012018','DDMMYYYY')
and start_date_local >= TO_DATE('01012026','DDMMYYYY')
and type IN('VirtualRide','Ride')
group by trunc(start_date_local,'mm')
)
select a.start_date_local
, distance_km
, TRUNC(elapsed_time/3600) || ':' || 
  LPAD(TRUNC(MOD(elapsed_time/60, 60)), 2, '0') || ':' || 
  LPAD(TRUNC(MOD(elapsed_time, 60)), 2, '0') elapsed_time
, TRUNC(moving_time/3600) || ':' || 
  LPAD(TRUNC(MOD(moving_time/60, 60)), 2, '0') || ':' || 
  LPAD(TRUNC(MOD(moving_time, 60)), 2, '0') moving_time
, ROUND(distance_km/moving_time*3600,2) avg_kmph
, num_activities
, elevation_gain
, ROUND(elevation_gain/distance_km,2) climb_per_km
, elevation_high, elevation_low
from a
order by 1
/




with d (my_date) as (
select TO_DATE('01012026','DDMMYYYY')+level-1
from dual
connect by level <= 366 --CEIL(sysdate-TO_DATE('01012026','DDMMYYYY'))
), a as (
select trunc(a.start_date_local) start_date_local
, count(*) num_activities
, sum(elapsed_time) elapsed_time
, sum(moving_time) moving_time
, sum(distance_km) distance_km
, sum(elevation_gain) elevation_gain
, max(elevation_high) elevation_high
, min(elevation_low) elevation_low
, listagg(distinct a.activity_id,',') within group (order by distance_km desc) activity_ids
from activities a
where start_date_local >= TO_DATE('01012018','DDMMYYYY')
and type IN(/*'VirtualRide',*/'Ride')
group by trunc(start_date_local)
)
select d.my_date
, distance_km
, TRUNC(elapsed_time/3600) || ':' || 
  LPAD(TRUNC(MOD(elapsed_time/60, 60)), 2, '0') || ':' || 
  LPAD(TRUNC(MOD(elapsed_time, 60)), 2, '0') elapsed_time
, TRUNC(moving_time/3600) || ':' || 
  LPAD(TRUNC(MOD(moving_time/60, 60)), 2, '0') || ':' || 
  LPAD(TRUNC(MOD(moving_time, 60)), 2, '0') moving_time
, ROUND(distance_km/moving_time*3600,2) avg_kmph
--, num_activities
, elevation_gain
, ROUND(elevation_gain/distance_km,2) climb_per_km
, elevation_high, elevation_low
, activity_ids
from d 
inner /*left outer*/ join a on a.start_date_local = d.my_date
where d.my_date < sysdate
--and a.distance_km > 10
order by 1 desc
--, climb_per_km desc nulls last
/

REM top 5 countries by distance, with elevation and average climb per km
with a as (
select m.name
, count(*) num_activities
, sum(elapsed_time) elapsed_time
, sum(moving_time) moving_time
, sum(distance_km) distance_km
, sum(elevation_gain) elevation_gain
--, max(elevation_high) elevation_high
--, min(elevation_low) elevation_low
from my_areas m --countries
  inner join activity_areas aa on aa.area_code = m.area_code and aa.area_number = m.area_number
  inner join activities a on a.activity_id = aa.activity_id
where m.parent_area_code IS NULL
and a.start_date_local >= TO_DATE('01012020','DDMMYYYY')
and a.type IN(/*'VirtualRide',*/'Ride')
group by m.name
)
select a.name
, distance_km
, TRUNC(elapsed_time/3600) || ':' || 
  LPAD(TRUNC(MOD(elapsed_time/60, 60)), 2, '0') || ':' || 
  LPAD(TRUNC(MOD(elapsed_time, 60)), 2, '0') elapsed_time
, TRUNC(moving_time/3600) || ':' || 
  LPAD(TRUNC(MOD(moving_time/60, 60)), 2, '0') || ':' || 
  LPAD(TRUNC(MOD(moving_time, 60)), 2, '0') moving_time
, ROUND(distance_km/moving_time*3600,2) avg_kmph
, num_activities
, elevation_gain
, ROUND(elevation_gain/distance_km,2) climb_per_km
--, elevation_high, elevation_low
from a
order by distance_km desc
fetch first 5 rows only
/