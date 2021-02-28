load_FRA.sql

#cd /tmp/strava/
#ln -s /vagrant/files/load_shapes.sh ./
#unzip /vagrant/files/FRA_adm.zip -d /tmp/strava/
#/tmp/strava/load_shapes.sh

set pages 99 lines 180 timi on
desc FRA_adm1

break on area_level skip 1
select * from my_area_codes
order by area_level, area_code
/

select distinct engtype_1 from FRA_adm1;
select distinct engtype_2 from FRA_adm2;
select distinct engtype_3 from FRA_adm3;
select distinct engtype_4 from FRA_adm4;
select distinct engtype_5 from FRA_adm5;


update FRA_adm3 set engtype_3 = 'District' where engtype_3 = 'Districts';
update FRA_adm4 set engtype_4 = 'Canton' where engtype_4 = 'Cantons';

--insert into my_area_codes values 
insert into my_area_codes values ('REG','Region',5);
insert into my_area_codes values ('DEPT','Department',6);
insert into my_area_codes values ('CANT','Canton',7);
insert into my_area_codes values ('COMM','Commune',8);

--delete corsica
delete from my_Areas2
where area_code = 'GEOS'
and area_number = 1159320673;


--merge regions into area
merge into my_areas2 u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_Areas2 where name IN('France')
and area_code = 'GEOU'
and area_number = 1159320651
)
select c.area_code, LTRIM(TO_CHAR(x.id_0,'000'))||'1'
                  ||LTRIM(TO_CHAR(x.id_1,'00')) area_number, x.iso||'A'||x.id_1 uqid, x.name_1 name, geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, c.area_level
from FRA_adm1 x, my_area_codes c, p
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


--merge departments into area
merge into my_areas2 u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_Areas2 
where parent_area_code = 'GEOU'
and parent_area_number = 1159320651
)
select c.area_code, LTRIM(TO_CHAR(x.id_0,'000'))||'2'
				  ||LTRIM(TO_CHAR(x.id_2,'000')) area_number, x.iso||'B'||x.id_2 uqid, x.name_2, geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, 6 area_level
from FRA_adm2 x, my_area_codes c, p
where c.description = x.engtype_2
and p.area_number = LTRIM(TO_CHAR(x.id_0,'000'))||'1'
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

--merge distrinct into area
merge into my_areas2 u
using (
select c.area_code, LTRIM(TO_CHAR(x.id_0,'000'))||'3'
				  ||LTRIM(TO_CHAR(x.id_3,'000')) area_number, x.iso||'C'||x.id_3 uqid, x.name_3, x.geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, 7 area_level
from FRA_adm3 x, my_area_codes c, my_areas2 p
where c.description = x.engtype_3
and p.area_code = 'DEPT'
and LTRIM(TO_CHAR(x.id_0,'000'))||'2'
  ||LTRIM(TO_CHAR(x.id_2,'000')) = p.area_number
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
,s.area_level ,s.name_3
,s.geom ,sdo_geom.sdo_mbr(s.geom)
);

--merge cantons into area
merge into my_areas2 u
using (
select c.area_code, LTRIM(TO_CHAR(x.id_0,'000'))||'4'
				  ||LTRIM(TO_CHAR(x.id_4,'0000')) area_number, x.iso||'D'||x.id_4 uqid, x.name_4
, x.geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, 8 area_level
from FRA_adm4 x, my_area_codes c, my_areas2 p
where c.description = x.engtype_4
and c.area_code = 'CANT'
and p.area_code = 'DIS'
and LTRIM(TO_CHAR(x.id_0,'000'))||'3'
  ||LTRIM(TO_CHAR(x.id_3,'000')) = p.area_number
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
,s.area_level ,s.name_4
,s.geom ,sdo_geom.sdo_mbr(s.geom)
);

--merge communes into area
merge into my_areas2 u
using (
select c.area_code, LTRIM(TO_CHAR(x.id_0,'000'))||'5'
				  ||LTRIM(TO_CHAR(x.id_5,'00000')) area_number, x.iso||'E'||x.id_5 uqid, x.name_5
, x.geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, 8 area_level
from FRA_adm5 x, my_area_codes c, my_areas2 p
where c.description = x.engtype_5
and c.area_code = 'COMM'
and p.area_code = 'CANT'
and LTRIM(TO_CHAR(x.id_0,'000'))||'4'
  ||LTRIM(TO_CHAR(x.id_4,'0000')) = p.area_number
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
,s.area_level ,s.name_5
,s.geom ,sdo_geom.sdo_mbr(s.geom)
);

set pages 99 lines 180 timi on
select level, m.area_code, m.area_number, m.uqid, m.name, m.parent_area_code, m.parent_area_number, m.parent_uqid, m.area_level
from my_areas2 m
start with name IN('France') and area_code = 'SOV' and area_number = 1159320629
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
and a1.area_code = 'GEOU'
and a1.area_number = 1159320651
--and rownum = 1
  ) LOOP
    strava_pkg.activity_area_search(i.activity_id,i.area_code,i.area_number);
    commit;
  END LOOP;
END;
/
