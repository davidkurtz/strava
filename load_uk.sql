REM load_uk.sql

alter table my_areas modify name varchar2(60);
alter table my_area_codes modify description varchar2(40);

insert into my_area_codes values ('CCTY','Ceremonial County',5);
insert into my_area_codes values ('AONB','Area of Outstanding Natural Beauty',5);
--update my_areas set area_level = 5 where area_code = 'CCTY';
insert into my_area_codes values ('SCC','Scottish Community Council',7);

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
--England/Scotland/Wales are level 3 geounit

desc county_region
select distinct area_code
from county_region
order by 1
/

insert into my_area_codes (area_Code, description, area_level)
with x as (
select area_code, descriptio from county_region
minus select area_Code, description from my_Area_codes
)
select area_Code, descriptio,5
from x
/

select area_Code, area_number, uqid, area_level, name
from my_areas where area_code='GEOU'
and name IN('England','Scotland','Wales')
/

delete from my_areas
where area_level >= 5;

update my_areas
set geom_27700 = sdo_cs.transform(geom,27700)
where area_code='GEOU'
and name IN('England','Scotland','Wales')
/

merge into my_areas u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_areas where area_code='GEOU'
and name IN('England','Scotland','Wales')
)
select x.*, x.polygon_id area_number, a.area_level
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
from county_region x, my_area_codes a, p
where x.area_code = a.area_code
and p.name = DECODE(substr(x.code,1,1),'E','England','W','Wales','S','Scotland')
and p.area_level < a.area_level
) s
on (u.area_code = s.area_code
and u.area_number = s.area_number)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.area_level ,u.name 
,u.geom, u.geom_27700 ,u.mbr)
values 
(s.area_Code, s.area_number ,s.code 
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.area_level ,s.name
,sdo_cs.transform(s.geom_27700,4326) ,s.geom_27700 ,sdo_cs.transform(sdo_geom.sdo_mbr(s.geom_27700),4326))
/

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
desc district_borough_unitary_region
select distinct area_code
from district_borough_unitary_region
order by 1
/

insert into my_area_codes (area_Code, description, area_level)
with x as (
select area_code, descriptio from district_borough_unitary_region
minus select area_Code, description from my_Area_codes
)
select area_Code, descriptio,6
from x
/

merge into my_areas u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_areas where area_code='GEOU'
and name IN('England','Scotland','Wales')
), x as (
select x.*, a.area_level
from district_borough_unitary_region x
inner join my_area_codes a
  on a.area_code = x.area_code 
)
select x.*, x.polygon_id area_number
, NVL(c.area_code,p.area_code) parent_area_Code
, NVL(c.polygon_id,p.area_number) parent_area_number
, NVL(c.code,p.uqid) parent_uqid
from x
left outer join county_region c
  on c.file_name = x.file_name
left outer join p
  on  p.name = DECODE(substr(x.code,1,1),'E','England','W','Wales','S','Scotland')
  and p.area_level < x.area_level
) s
on (u.area_code = s.area_code
and u.area_number = s.area_number)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.area_level ,u.name 
,u.geom, u.geom_27700 ,u.mbr)
values 
(s.area_Code, s.area_number ,s.code 
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.area_level ,s.name
,sdo_cs.transform(s.geom_27700,4326) ,s.geom_27700 ,sdo_cs.transform(sdo_geom.sdo_mbr(s.geom_27700),4326))
/
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
desc district_borough_unitary_ward_region
select distinct area_code
from district_borough_unitary_ward_region
order by 1
/

insert into my_area_codes (area_Code, description, area_level)
with x as (
select area_code, descriptio from district_borough_unitary_ward_region
minus select area_Code, description from my_Area_codes
)
select area_Code, descriptio,7
from x
/

merge into my_areas u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_areas where area_code='GEOU'
and name IN('England','Scotland','Wales')
), x as (
select x.*, a.area_level
from district_borough_unitary_ward_region x
inner join my_area_codes a
  on a.area_code = x.area_code 
), d as (
select max(d.area_code) area_code, d.file_name, MAX(d.polygon_id) polygon_id, max(d.code) code
from district_borough_unitary_region d
group by file_name
having count(*) = 1
)
select x.*, x.polygon_id area_number
, COALESCE(d.area_code,c.area_code,p.area_code) parent_area_Code
, COALESCE(d.polygon_id,c.polygon_id,p.area_number) parent_area_number
, COALESCE(d.code,c.code,p.uqid) parent_uqid
, row_number() over (partition by x.code order by x.hectares desc) seq
from x
left outer join d
  on d.file_name = x.file_name
left outer join county_region c
  on c.file_name = x.file_name
left outer join p
  on  p.name = DECODE(substr(x.code,1,1),'E','England','W','Wales','S','Scotland')
  and p.area_level < x.area_level
) s
on (u.area_code = s.area_code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_Code = s.parent_area_Code
, u.parent_area_number = s.parent_area_number
, u.parent_uqid = s.parent_uqid
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.area_level ,u.name 
,u.geom, u.geom_27700 ,u.mbr)
values 
(s.area_Code, s.area_number 
,s.code ||CASE WHEN seq>1 THEN CHR(64+seq) END
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.area_level ,s.name
,sdo_cs.transform(s.geom_27700,4326) ,s.geom_27700 ,sdo_cs.transform(sdo_geom.sdo_mbr(s.geom_27700),4326))
/
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
--CPC/NPC
desc parish_region
select distinct area_code
from parish_region
order by 1
/

insert into my_area_codes (area_Code, description, area_level)
with x as (
select area_code, descriptio from parish_region
minus select area_Code, description from my_Area_codes
)
select area_Code, descriptio,7
from x
/

merge into my_areas u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_areas where area_code='GEOU'
and name IN('England','Scotland','Wales')
), x as (
select x.*, a.area_level
from parish_region x
inner join my_area_codes a
  on a.area_code = x.area_code 
where polygon_id > 0
and code is not null
and name is not null
and DESCRIPT0 != 'FILLER AREA'
), d as (
select max(d.area_code) area_code, d.file_name, MAX(d.polygon_id) polygon_id, max(d.code) code
from district_borough_unitary_region d
group by file_name
having count(*) = 1
)
select x.*, x.polygon_id area_number
, COALESCE(d.area_code,c.area_code,p.area_code) parent_area_Code
, COALESCE(d.polygon_id,c.polygon_id,p.area_number) parent_area_number
, COALESCE(d.code,c.code,p.uqid) parent_uqid
, row_number() over (partition by x.code order by x.hectares desc) seq
from x
left outer join d
  on d.file_name = x.file_name
left outer join county_region c
  on c.file_name = x.file_name
left outer join p
  on  p.name = DECODE(substr(x.code,1,1),'E','England','W','Wales','S','Scotland')
  and p.area_level < x.area_level
) s
on (u.area_code = s.area_code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_Code
, u.parent_area_number = s.parent_area_number
, u.parent_uqid  = s.parent_uqid
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.area_level ,u.name 
,u.geom, u.geom_27700 ,u.mbr)
values 
(s.area_Code, s.area_number 
,s.code ||CASE WHEN seq>1 THEN CHR(64+seq) END
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.area_level ,s.name
,sdo_cs.transform(s.geom_27700,4326) ,s.geom_27700 ,sdo_cs.transform(sdo_geom.sdo_mbr(s.geom_27700),4326))
/
----------------------------------------------------------------------------------------------------
REM ...spatial match district that contains the ward...look at level 7 areas who don not have a level 6 parent and do a spatial match

REM rough match
merge into my_areas u
using (
select m.area_code, m.area_number, m.uqid, m.name
,      MAX(m2.area_code) parent_area_code
,      MAX(m2.area_number) parent_area_number
,      MAX(m2.uqid) parent_uqid
,      MAX(m2.name) parent_name
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level = m.area_level-1
where m.area_level  = 7
and   c.area_level = m.area_level-2
--and   m.parent_area_number = 44204 /*Norts Herts*/
and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
group by m.area_code, m.area_number, m.uqid, m.name
having count(*) = 1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/

REM exact match - can take time - might not find anything!
merge into my_areas u
using (
select m.area_code, m.area_number, m.uqid, m.name
,      MAX(m2.area_code) parent_area_code
,      MAX(m2.area_number) parent_area_number
,      MAX(m2.uqid) parent_uqid
,      MAX(m2.name) parent_name
,      count(*) num_matches
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code 
                      and m2.parent_area_number = m.parent_area_number 
					  and m2.area_level = m.area_level-1
where m.area_level  = 7
and   c.area_level = m.area_level-2
--and   m.parent_area_number = 49530
and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and   sdo_geom.relate(m2.geom_27700,'COVERS+CONTAINS+EQUAL',m.geom_27700,25) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
--and   sdo_geom.sdo_area(sdo_geom.sdo_intersection(m2.geom_27700,m.geom_27700,25))>0
and   m.geom_27700 IS NOT NULL
and   m2.geom_27700 IS NOT NULL
and   m.area_code IN('CPC','LBW','DIW')
and   m2.area_code IN('DIS','LBO')
--and 1=2 --disabled because found nothing
group by m.area_code, m.area_number, m.uqid, m.name
having count(*) = 1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/

REM best match -London
merge into my_areas u
using (
with x as (
select m.area_code, m.area_number, m.uqid, m.name
,      (m2.area_code) parent_area_code
,      (m2.area_number) parent_area_number
,      (m2.uqid) parent_uqid
,      (m2.name) parent_name
,      sdo_geom.sdo_area(sdo_geom.sdo_intersection(m2.geom_27700,m.geom_27700,25)) area
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level = m.area_level-1
where m.area_level  = 7
and   c.area_level = m.area_level-2
--and   m.parent_area_number = 49530
and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
--and   sdo_geom.relate(m2.geom_27700,'COVERS+CONTAINS+EQUAL',m.geom_27700,25) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and   m.geom_27700 IS NOT NULL
and   m2.geom_27700 IS NOT NULL
and   m.area_code IN('LBW')
and   m2.area_code IN('LBO')
), y as (
select x.* 
,      row_number() over (partition by area_code, area_number order by area desc) seq
from   x
where  area>0
)
select y.*
from   y
where  seq=1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/

REM best match Not London --this can be slow
merge into my_areas u
using (
with x as (
select m.area_code, m.area_number, m.uqid, m.name
,      (m2.area_code) parent_area_code
,      (m2.area_number) parent_area_number
,      (m2.uqid) parent_uqid
,      (m2.name) parent_name
,      sdo_geom.sdo_area(sdo_geom.sdo_intersection(m2.geom_27700,m.geom_27700,25)) area
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level = m.area_level-1
where m.area_level  = 7
and   c.area_level = m.area_level-2
--and   m.parent_area_number = 49530
and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
--and   sdo_geom.relate(m2.geom_27700,'COVERS+CONTAINS+EQUAL',m.geom_27700,25) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and   m.geom_27700 IS NOT NULL
and   m2.geom_27700 IS NOT NULL
and   m.area_code IN('CPC','DIW')
and   m2.area_code IN('DIS')
), y as (
select x.* 
,      row_number() over (partition by area_code, area_number order by area desc) seq
from   x
where  area>0
)
select y.*
from   y
where  seq=1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/


REM unmatched types
select distinct m.area_code, m2.area_code, m.parent_area_Code
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level = m.area_level-1
where m.area_level  = 7
and   c.area_level = m.area_level-2
--and   m.parent_area_number = 49530
--and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
--and   sdo_geom.relate(m2.geom_27700,'COVERS+CONTAINS+EQUAL',m.geom_27700,25) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
/


REM unmatched
select m.area_code, m.area_number, m.uqid, m.name
,      MAX(m2.area_code) parent_area_code
,      MAX(m2.area_number) parent_area_number
,      MAX(m2.uqid) parent_uqid
,      MAX(m2.name) parent_name
, count(*)
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level = m.area_level-1
where m.area_level  = 7
and   c.area_level = m.area_level-2
--and   m.parent_area_number = 49530
--and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
--and   sdo_geom.relate(m2.geom_27700,'COVERS+CONTAINS+EQUAL',m.geom_27700,25) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
--and   m.area_code IN('LBW')
--and   m2.area_code IN('LBO')
group by m.area_code, m.area_number, m.uqid, m.name
/

select m.area_code, m.area_number, m.uqid, m.name
,      (m2.area_code) parent_area_code
,      (m2.area_number) parent_area_number
,      (m2.uqid) parent_uqid
,      (m2.name) parent_name
,      sdo_geom.relate(m2.geom_27700,'determine',m.geom_27700,25)
,      sdo_geom.sdo_area(sdo_geom.sdo_intersection(m2.geom_27700,m.geom_27700,25))
--, count(*)
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level = m.area_level-1
where m.area_level  = 7
and   c.area_level = m.area_level-2
--and   m.area_number = 49413
--and   m.parent_area_number = 49530
and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and   sdo_geom.relate(m2.geom_27700,'COVERS+CONTAINS+EQUAL',m.geom_27700,25) = 'COVERS+CONTAINS+EQUAL' 
order by 1,2,3
/

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
desc BOUNDARY_LINE_CEREMONIAL_COUNTIES_REGION

merge into my_areas u
using (
with p as (
select /*+MATERIALIZE*/ area_Code parent_area_Code, area_number parent_area_number, uqid parent_uqid
from my_areas where area_code='SOV'
and name IN('United Kingdom')
), x as (
select /*+MATERIALIZE*/ row_number() over (order by name) area_number, x.* from BOUNDARY_LINE_CEREMONIAL_COUNTIES_REGION x
)
select p.*
, x.area_number, x.name , x.mbr, x.geom_27700
, c.area_code, c.area_level
from x, my_area_codes c, p
where c.area_code = 'CCTY'
and not exists(
  select 'x' from my_areas m 
  where  m.area_code != c.area_code
  and m.area_level >= 4
  and (m.name = x.name 
    OR m.name = 'County '||x.name 
    OR m.name = 'County of '||x.name
    OR m.name = 'City of '||x.name
    OR m.name = x.name||' City'
  ))
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.area_level ,u.name 
,u.geom, u.geom_27700 ,u.mbr)
values 
(s.area_Code, s.area_number ,s.area_code||s.area_number 
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.area_level ,s.name
,NULL ,s.geom_27700 ,s.mbr)
/


update my_areas s
set geom = CASE area_number WHEN 87 THEN NULL ELSE sdo_cs.transform(s.geom_27700,4326) END
where geom_27700 IS NOT NULL
and geom is null
and not (area_code = 'CCTY' and area_number = 87)
;

--simplifying the western isles to reduce number of points before conversion to 4326
update my_areas s
set geom = sdo_cs.transform(sdo_util.simplify(geom_27700,10),4326)
where geom_27700 IS NOT NULL
and area_code = 'CCTY'
and area_number = 87
;


select area_code, area_number, name
, SDO_UTIL.GETNUMVERTICES(geom)
, SDO_UTIL.GETNUMVERTICES(geom_27700)
--, SDO_UTIL.GETNUMVERTICES(sdo_util.simplify(geom_27700,10))
from my_areas
where area_code = 'CCTY'
and area_number = 87
order by area_number
/


UPDATE my_areas u
set (u.parent_area_code, u.parent_area_number, u.parent_uqid
) = (
   select s.area_code, s.area_number, s.uqid
   from my_areas s
   where s.area_Code = 'GEOU' AND s.area_Number = 1159320747 and s.name = 'Scotland')
where u.area_code = 'CCTY' and u.area_number IN(26,78,87) /*western isles*/
/
UPDATE my_areas u
set (u.parent_area_code, u.parent_area_number, u.parent_uqid
) = (
   select s.area_code, s.area_number, s.uqid
   from my_areas s
   where s.area_Code = 'GEOU' and s.name = 'Wales' AND s.area_Number = 1159320749 )
where u.area_code = 'CCTY' and u.area_number IN(82,52,64,20)
/
UPDATE my_areas u
set (u.parent_area_code, u.parent_area_number, u.parent_uqid
) = (
   select s.area_code, s.area_number, s.uqid
   from my_areas s
   where s.area_Code = 'GEOU' and s.name = 'England' AND s.area_Number = 1159320743 )
where u.area_code = 'CCTY' and u.area_number IN(80)
/


REM rough match
merge into my_areas u
using (
select m.area_code, m.area_number, m.uqid, m.name
,      MAX(m2.area_code) parent_area_code
,      MAX(m2.area_number) parent_area_number
,      MAX(m2.uqid) parent_uqid
,      MAX(m2.name) parent_name
,      count(*) num_matches
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level <= m.area_level-2
where m.area_level  = 5
and   c.area_level <= m.area_level-2
and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
group by m.area_code, m.area_number, m.uqid, m.name
having count(*) = 1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/

REM exact match
merge into my_areas u
using (
select m.area_code, m.area_number, m.uqid, m.name
,      MAX(m2.area_code) parent_area_code
,      MAX(m2.area_number) parent_area_number
,      MAX(m2.uqid) parent_uqid
,      MAX(m2.name) parent_name
,      count(*) num_matches
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level <= m.area_level-2
where m.area_level  = 5
and   c.area_level <= m.area_level-2
and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and   sdo_geom.relate(m2.geom_27700,'COVERS+CONTAINS+EQUAL',m.geom_27700,25) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
--and   sdo_geom.sdo_area(sdo_geom.sdo_intersection(m2.geom_27700,m.geom_27700,25))>0
group by m.area_code, m.area_number, m.uqid, m.name
having count(*) = 1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
REM Scottish Community Council
desc pub_commcnc

alter table pub_commcnc Add mbr mdsys.sdo_geometry;
UPDATE pub_commcnc
SET mbr = sdo_cs.transform(sdo_geom.sdo_mbr(geom_27700),4326)
/

merge into my_areas u
using (
with d as (
select area_code, area_number, uqid, area_level, name
from my_areas
where area_code IN('UTA')
)
select x.*
, TO_NUMBER(SUBSTR(la_s_code,7)||LTRIM(TO_CHAR(sh_src_id,'000'))) area_number 
, la_s_code||TO_CHAR(-sh_src_id,'000') uqid
, c.area_code, c.area_level
, d.area_code parent_area_Code, d.area_Number parent_area_number, d.uqid parent_uqid
, sdo_cs.transform(x.geom_27700,4326) geom
from pub_commcnc x, d
, my_area_codes c
where d.name = x.local_auth
and   c.area_code = 'SCC'
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.area_level ,u.name 
,u.geom, u.geom_27700 ,u.mbr)
values 
(s.area_Code, s.area_number ,s.uqid
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.area_level ,s.cc_name
,s.geom ,s.geom_27700 ,s.mbr)
/

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
REM AONB
desc AONB

merge into my_areas u
using (
with p as (
select /*+MATERIALIZE*/ area_Code parent_area_Code, area_number parent_area_number, uqid parent_uqid
from my_areas where area_code='SOV'
and name IN('United Kingdom')
)
select p.*
, x.unique_id_number area_number
, c.area_code||x.code uqid
, x.name
, x.geom_27700
, c.area_code, c.area_level
from AONB x, my_area_codes c, p
where c.area_code = 'AONB'
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.area_level ,u.name 
,u.geom, u.geom_27700 ,u.mbr)
values 
(s.area_Code, s.area_number ,s.area_code||s.area_number 
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.area_level ,s.name
,sdo_cs.transform(s.geom_27700,4326) ,s.geom_27700 ,sdo_cs.transform(sdo_geom.sdo_mbr(s.geom_27700),4326))
/




REM rough match
merge into my_areas u
using (
select m.area_code, m.area_number, m.uqid, m.name
,      MAX(m2.area_code) parent_area_code
,      MAX(m2.area_number) parent_area_number
,      MAX(m2.uqid) parent_uqid
,      MAX(m2.name) parent_name
,      count(*) num_matches
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level <= m.area_level-2
where m.area_code = 'AONB'
and   c.area_level <= m.area_level-2
and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
group by m.area_code, m.area_number, m.uqid, m.name
having count(*) = 1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/

REM exact match
merge into my_areas u
using (
select m.area_code, m.area_number, m.uqid, m.name
,      MAX(m2.area_code) parent_area_code
,      MAX(m2.area_number) parent_area_number
,      MAX(m2.uqid) parent_uqid
,      MAX(m2.name) parent_name
,      count(*) num_matches
from my_areas m
inner join my_area_codes c on c.area_code = m.parent_area_code
inner join my_areas m2 on m2.parent_area_Code = m.parent_area_Code and m2.parent_area_number = m.parent_area_number and m2.area_level <= m.area_level-2
where m.area_code = 'AONB'
and   c.area_level <= m.area_level-2
and   sdo_geom.relate(m2.mbr,'COVERS+CONTAINS+EQUAL',m.mbr,10) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and   sdo_geom.relate(m2.geom_27700,'COVERS+CONTAINS+EQUAL',m.geom_27700,25) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and   sdo_geom.sdo_area(sdo_geom.sdo_intersection(m2.geom_27700,m.geom_27700,25))>0
group by m.area_code, m.area_number, m.uqid, m.name
having count(*) = 1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/

update my_areas
set parent_area_Code = 'GEOU'
,   parent_area_number = '1159320743'
,   parent_uqid = 'NE1159320743'
where area_Code = 'AONB'
and area_number IN(2,7,13)
/

set lines 180
select area_code, area_number, name, parent_area_code, parent_area_number, parent_uqid
from my_areas
where area_code = 'AONB'
order by 4,5,1,2
/

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
delete from my_areas x
where x.area_code = 'CCTY'
and exists(
  select 'x' from my_areas y
  where y.area_code != x.area_code
  and x.name = y.name);

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
REM make UTA/MTD children of CCTY 

merge into my_areas u
using (
with x as (
select m.area_code, m.area_number, m.name
,      mc.area_code parent_area_code
,      mc.area_number parent_area_number
,      mc.uqid parent_uqid
,      mc.name parent_name
,      count(*) over (partition by m.area_code, m.area_number) num_matches 
,      sdo_geom.relate(mc.geom_27700,'determine',m.geom_27700)
from   my_areas m
--,      my_areas mp
,      my_areas mc
where  m.area_code IN('UTA','MTD')
--and    mp.area_code = m.parent_area_Code
--and    mp.area_number = m.parent_area_number
and    m.parent_area_code = 'GEOU'
and    m.parent_area_number IN(1159320743 --England
                              ,1159320747 --Scotland
                              ,1159320749) --Wales
and    mc.area_code = 'CCTY'
and    mc.parent_area_Code = m.parent_area_Code
and    mc.parent_area_number = m.parent_area_number
and    sdo_geom.relate(mc.mbr,'COVERS+CONTAINS+EQUAL',m.mbr) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and    sdo_geom.relate(mc.geom_27700,'COVERS+CONTAINS+EQUAL',m.geom_27700) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and    mc.name = 'Berkshire'
)
select * from x 
where num_matches = 1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/
