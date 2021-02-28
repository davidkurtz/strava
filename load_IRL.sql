load_IRL.sql

#https://data.biogeo.ucdavis.edu/data/diva/adm/IRL_adm.zip
#cd /tmp/strava/
#ln -s /vagrant/files/load_shapes.sh ./
#unzip /vagrant/files/IRL_adm.zip -d /tmp/strava/
#load_shapes.sh

set pages 99 lines 180
desc IRL_adm1

select distinct type_1 from irl_adm1;

break on area_level skip 1
select * from my_area_codes
order by area_level, area_code
/

insert into my_area_codes values ('TCTY','Traditional County',5);
insert into my_area_codes values ('ACTY','Administrative County',5);

--merge counties into country
merge into my_areas2 u
using (
with p as (
select area_Code, area_number, uqid, area_level, name
from my_Areas2 where name IN('Ireland')
and area_code = 'SOVC'
)
select c.area_code, x.id_1 area_number, x.iso||x.id_1 uqid, x.name_1 name, x.geom
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid
, c.area_level
from irl_adm1 x, my_area_codes c, p
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

select level, m.name, m.parent_area_code, m.parent_area_number, m.area_level
from my_areas2 m
start with m.name = 'Ireland'
--m.parent_area_code is null and m.parent_area_number is null
connect by prior m.area_code = m.parent_area_code and prior m.area_number = m.parent_area_number
/

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

set serveroutput on
BEGIN 
  FOR i IN(
select a1.area_code, a1.area_number, a1.name, b1.activity_id
from my_areas2 a1, activity_areas b1
where a1.area_code = b1.area_code
and a1.area_number = b1.area_number
and a1.num_children > 0
and a1.area_code = 'SOVC'
and a1.area_number = 1159320877
--and rownum = 1
  ) LOOP
    strava_pkg.activity_area_search(i.activity_id);
    commit;
  END LOOP;
END;
/