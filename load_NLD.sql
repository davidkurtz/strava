load_NLD.sql

#cd /tmp/strava/
#ln -s /vagrant/files/load_shapes.sh ./
#unzip /vagrant/files/NLD_adm.zip -d /tmp/strava/
#/tmp/strava/load_shapes.sh

set pages 99 lines 180 timi on
desc NLD_adm1

break on area_level skip 1
select * from my_area_codes
order by area_level, area_code
/

select distinct engtype_1 from NLD_adm1;
select distinct engtype_2 from NLD_adm2;


insert into my_area_codes values ('PROV','Province',5);
insert into my_area_codes values ('MUNC','Municipality',6);
insert into my_area_codes values ('WAT','Water body',5);
--insert into my_area_codes values 

--merge provinces into area
merge into my_areas u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_areas where name IN('Netherlands')
and area_code = 'GEOC'
)
select c.area_code, LTRIM(TO_CHAR(x.id_0,'000'))
                  ||LTRIM(TO_CHAR(x.id_1,'00')) area_number, x.iso||x.id_1 uqid, x.name_1 name, geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, c.area_level
from NLD_adm1 x, my_area_codes c, p
where c.description = x.engtype_1
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


--merge municipalities into area
merge into my_areas u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_areas 
where parent_area_number IN(1159321105)
and parent_area_code = 'GEOC'
)
select c.area_code, LTRIM(TO_CHAR(x.id_0,'000'))
                  ||LTRIM(TO_CHAR(x.id_1,'00'))
				  ||LTRIM(TO_CHAR(x.id_2,'000')) area_number, x.iso||x.id_1||'.'||x.id_2 uqid, x.name_2, geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, 6 area_level
from NLD_adm2 x, my_area_codes c, p
where c.description = x.engtype_2
and p.area_number = LTRIM(TO_CHAR(x.id_0,'000'))
                  ||LTRIM(TO_CHAR(x.id_1,'00'))
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
from my_areas m
start with name IN('Netherlands') and area_code = 'SOV'
--m.parent_area_code is null and m.parent_area_number is null
connect by prior m.area_code = m.parent_area_code and prior m.area_number = m.parent_area_number
/

--recalc number children
update my_areas p
set p.num_children = (select NULLIF(count(*),0)
  from my_areas c
  where c.parent_area_Code = p.area_Code
  and   c.parent_area_number = p.area_number
  and   c.parent_uqid = p.uqid)
/

--areas with children, but none of children identified
select a1.area_code, a1.area_number, a1.name, count(*)
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
group by a1.area_code, a1.area_number, a1.name
/

--analyse activities affected by new areas
set serveroutput on
BEGIN 
  FOR i IN(
select a1.area_code, a1.area_number, a1.name, b1.activity_id
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
and a1.area_code = 'GEOC'
and a1.area_number = 1159321105
and rownum = 1
  ) LOOP
    strava_pkg.activity_area_search(i.activity_id,i.area_code,i.area_number);
--    commit;
  END LOOP;
END;
/
