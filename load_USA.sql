load_USA.sql

#cd /tmp/strava/
#ln -s /vagrant/files/load_shapes.sh ./
#unzip /vagrant/files/USA_adm.zip -d /tmp/strava/
#/tmp/strava/load_shapes.sh

set pages 99 lines 180 timi on
desc USA_adm1

select distinct type_1 from USA_adm1;
select distinct type_2 from USA_adm2;

break on area_level skip 1
select * from my_area_codes
order by area_level, area_code
/

--delete from activity_areas where area_code IN('STAT','FDIS');
--delete from my_areas2 where area_code IN('STAT','FDIS');

insert into my_area_codes values ('STAT','State',5);
insert into my_area_codes values ('FDIS','Federal District',5);
insert into my_area_codes values ('CITY','City',6);
insert into my_area_codes values ('BORO','Borough',6);
insert into my_area_codes values ('MUNC','Municipality',6);
insert into my_area_codes values ('PAR','Parish',6);
insert into my_area_codes values ('CITI','Independent City',6);
insert into my_area_codes values ('CITB','City and Borough',6);
insert into my_area_codes values ('CITC','City and County',6);
--insert into my_area_codes values ('WAT','Water Body',6);
--insert into my_area_codes values 

--merge states into area
merge into my_areas2 u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_Areas2 where name IN('United States of America')
and area_code = 'CTRY'
)
select c.area_code, LTRIM(TO_CHAR(x.id_0,'000'))
                  ||LTRIM(TO_CHAR(x.id_1,'00')) area_number, x.iso||x.id_1 uqid, x.name_1 name, geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, c.area_level
from USA_adm1 x, my_area_codes c, p
where c.description = x.type_1
) s
on (u.area_code = s.area_code
and u.area_number = s.area_number)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.area_level ,u.name 
,u.geom, u.mbr)
values 
(s.area_Code, s.area_number ,s.uqid 
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.area_level ,s.name
,s.geom ,sdo_geom.sdo_mbr(s.geom)
);

--rough match states to GEOS
merge into my_areas2 u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from   my_Areas2 where name IN('United States of America')
and    area_code = 'CTRY'
),x as(
select m.area_code, m.area_number, m.name
,      mc.area_code parent_area_code
,      mc.area_number parent_area_number
,      mc.uqid parent_uqid
,      mc.name parent_name
,      count(*) over (partition by m.area_code, m.area_number) num_matches 
--,      sdo_geom.relate(mc.mbr,'determine',m.mbr)
from   my_areas2 m
,      my_areas2 mc
,      p
where  m.area_code IN('STAT','FDIS')
and    m.parent_area_code = p.area_code
and    mc.area_code = 'GEOS'
and    mc.parent_area_Code = p.area_Code
and    mc.parent_area_number = p.area_number
and    sdo_geom.relate(mc.mbr,'COVERS+CONTAINS+EQUAL',m.mbr) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
)
select * from x where num_matches = 1
) s
on (u.area_Code = s.area_Code
and u.area_number = s.area_number)
when matched then update
set u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/

--exact match stats to GEOS
merge into my_areas2 u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from   my_Areas2 where name IN('United States of America')
and    area_code = 'CTRY'
),x as(
select m.area_code, m.area_number, m.name
,      mc.area_code parent_area_code
,      mc.area_number parent_area_number
,      mc.uqid parent_uqid
,      mc.name parent_name
,      count(*) over (partition by m.area_code, m.area_number) num_matches 
,      sdo_geom.relate(mc.geom,'determine',m.geom)
from   my_areas2 m
,      my_areas2 mc
,      p
where  m.area_code IN('STAT','FDIS')
and    m.parent_area_code = p.area_code
and    mc.area_code = 'GEOS'
and    mc.parent_area_Code = p.area_Code
and    mc.parent_area_number = p.area_number
--and    mc.area_Number = 1159321395
--and    m.area_number = 12
and    sdo_geom.relate(mc.geom,'COVERS+CONTAINS+EQUAL',m.geom) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
--and    sdo_geom.relate(mc.mbr,'COVERS+CONTAINS+EQUAL',m.mbr) = 'COVERS+CONTAINS+EQUAL' /*coarse filter first*/
and 1=2
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

--manual fixes
update my_areas2 
set parent_area_Code = 'GEOS'
,   parent_area_number = 1159321395 /*Hawaii*/
,   parent_uqid = 'NE1159321395'
where area_code = 'STAT' AND area_number = 24412;

update my_areas2 
set parent_area_Code = 'GEOS'
,   parent_area_number = 1159321397 /*Alaska*/
,   parent_uqid = 'NE1159321397'
where area_code = 'STAT' AND area_number = 24402;

update my_areas2 
set parent_area_Code = 'GEOS'
,   parent_area_number = 1159321393 /*Continental USA*/
,   parent_uqid = 'NE1159321393'
where area_code = 'STAT' AND area_number IN(24410,24424,24448);


--merge counties into area
merge into my_areas2 u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_Areas2 
where area_code IN('STAT','FDIS')
and parent_area_code = 'GEOS'
and parent_area_number IN(1159321393,1159321395,1159321397)
)
select c.area_code, LTRIM(TO_CHAR(x.id_0,'000'))
                  ||LTRIM(TO_CHAR(x.id_1,'00'))
                  ||LTRIM(TO_CHAR(x.id_2,'00')) area_number, x.iso||x.id_2 uqid, x.name_2, geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, 6 area_level
from USA_adm2 x, my_area_codes c, p
where c.description = x.type_2
and p.area_number = x.id_1
) s
on (u.area_code = s.area_code
and u.area_number = s.area_number)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.area_level ,u.name 
,u.geom, u.mbr)
values 
(s.area_Code, s.area_number ,s.uqid 
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.area_level ,s.name_2
,s.geom ,sdo_geom.sdo_mbr(s.geom)
);

set pages 99 lines 180 timi on
select level, m.area_code, m.area_number, m.uqid, m.name, m.parent_area_code, m.parent_area_number, m.parent_uqid, m.area_level
from my_areas2 m
start with name IN('United States of America') and area_code = 'CTRY'
--m.parent_area_code is null and m.parent_area_number is null
connect by prior m.area_code = m.parent_area_code and prior m.area_number = m.parent_area_number
/

--recalc number children
update my_Areas2 p
set p.num_children = (select NULLIF(count(*),0)
  from my_Areas2 c
  where c.parent_area_Code = p.area_Code
  and   c.parent_area_number = p.area_number
  and   c.parent_uqid = p.uqid)
/

--areas with children, but none of children identified
select a1.area_code, a1.area_number, a1.name, count(*)
from my_areas2 a1, activity_areas b1
where a1.area_code = b1.area_code
and a1.area_number = b1.area_number
and a1.num_children > 0
and not exists(
  select 'x'
  from my_areas2 a2, activity_areas b2
  where a2.area_code = b2.area_code
  and a2.area_number = b2.area_number
  and b2.activity_id = b1.activity_id
  and a2.parent_area_code = a1.area_code
  and a2.parent_area_number = a1.area_number)
group by a1.area_code, a1.area_number, a1.name
/

--analyse activities affected by new areas
set serveroutput on
BEGIN 
  FOR i IN(
select a1.area_code, a1.area_number, a1.name, b1.activity_id
from my_areas2 a1, activity_areas b1
where a1.area_code = b1.area_code
and a1.area_number = b1.area_number
and a1.num_children > 0
and not exists(
  select 'x'
  from my_areas2 a2, activity_areas b2
  where a2.area_code = b2.area_code
  and a2.area_number = b2.area_number
  and b2.activity_id = b1.activity_id
  and a2.parent_area_code = a1.area_code
  and a2.parent_area_number = a1.area_number)
and a1.area_code = 'GEOS'
and a1.area_number = 1159321393
--and rownum = 1
  ) LOOP
    strava_pkg.activity_area_search(i.activity_id,i.area_code,i.area_number);
    commit;
  END LOOP;
END;
/
