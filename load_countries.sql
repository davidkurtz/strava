REM load_countries.sql

set pages 99 lines 180 
desc ne_10m_admin_0_sovereignty

alter table my_areas modify name varchar2(60);
alter table my_area_codes modify description varchar2(40);

select distinct type, level_
from ne_10m_admin_0_sovereignty
/

truncate table my_area_codes;
insert into my_area_codes values ('SOV' ,'Sovereignty',1);

insert into my_area_codes values ('LEAS','Lease',2);
insert into my_area_codes values ('SOVC','Sovereign country',2);
insert into my_area_codes values ('IND' ,'Indeterminate',2);
insert into my_area_codes values ('CTRY','Country',2);
insert into my_area_codes values ('DEPC','Dependency',2);

insert into my_area_codes values ('GEOC','Geo core',3);
insert into my_area_codes values ('GEOU','Geo unit',3);
insert into my_area_codes values ('OVR3','Overlay',3);

insert into my_area_codes values ('GEOS','Geo subunit',4);
insert into my_area_codes values ('OVR4','Overlay',4);


select distinct type, level_ from ne_10m_admin_0_sovereignty minus 
select description, area_level from my_Area_codes;
----------------------------------------------------------------------------------------------------
truncate table my_areas;

merge into my_areas u
using (
select x.*, a.area_code
from ne_10m_admin_0_sovereignty x, my_area_codes a
where a.description = x.type
and a.area_level = x.level_
) s
on (u.area_code = s.area_code
and u.area_number = s.ne_id)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid ,u.wikidataid ,u.area_level ,u.name 
,u.iso_code3 ,u.iso_code2 ,u.iso_number 
,u.continent ,u.region_un ,u.subregion ,u.region_wb 
,u.geom ,u.mbr)
values 
(s.area_Code ,s.ne_id
,'NE'||s.ne_id ,s.wikidataid ,s.level_ ,s.admin
,NULLIF(s.sov_a3,'-99') ,NULLIF(s.iso_a2,'-99') ,NULLIF(s.iso_n3,'-99')
,s.continent ,s.region_un ,s.subregion ,s.region_wb 
,s.geom ,sdo_geom.sdo_mbr(s.geom))
/
commit;
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
desc ne_10m_admin_0_map_units
select distinct type, level_
from ne_10m_admin_0_map_units
order by 2,1
/

select type from ne_10m_admin_0_map_units
minus select description from my_Area_codes;

merge into my_areas u
using (
select x.*, a.area_code
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid 
from ne_10m_admin_0_map_units x, my_area_codes a, my_areas p
where a.description = x.type
and a.area_level = x.level_
and p.area_level < a.area_level
and p.iso_code3 = x.sov_a3
) s
on (u.area_code = s.area_code
and u.area_number = s.ne_id)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.wikidataid ,u.area_level ,u.name 
,u.iso_code3 ,u.iso_code2 ,u.iso_number 
,u.continent ,u.region_un ,u.subregion ,u.region_wb 
,u.geom ,u.mbr)
values 
(s.area_Code,s.ne_id
,'NE'||s.ne_id 
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.wikidataid ,s.level_ ,s.geounit
,NULLIF(s.gu_a3,'-99') ,NULLIF(s.iso_a2,'-99') ,NULLIF(s.iso_n3,'-99')
,s.continent ,s.region_un ,s.subregion ,s.region_wb 
,s.geom ,sdo_geom.sdo_mbr(s.geom))
/

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
desc ne_10m_admin_0_map_subunits
select distinct type, level_
from ne_10m_admin_0_map_subunits
order by 2,1
/

select type from ne_10m_admin_0_map_subunits
minus select description from my_Area_codes;

merge into my_areas u
using (
select x.*, a.area_code
, p.area_code parent_area_Code
, p.area_number parent_area_number
, p.uqid parent_uqid 
from ne_10m_admin_0_map_subunits x, my_area_codes a, my_areas p
where a.description = x.type
and a.area_level = x.level_
and p.area_level < a.area_level
and p.iso_code3 = x.gu_a3
) s
on (u.area_code = s.area_code
and u.area_number = s.iso_n3)
when not matched then insert 
(u.area_Code ,u.area_number ,u.uqid 
,u.parent_area_Code ,u.parent_area_number ,u.parent_uqid 
,u.wikidataid ,u.area_level ,u.name 
,u.iso_code3 ,u.iso_code2 ,u.iso_number 
,u.continent ,u.region_un ,u.subregion ,u.region_wb 
,u.geom ,u.mbr)
values 
(s.area_Code,s.ne_id
,'NE'||s.ne_id 
,s.parent_area_Code ,s.parent_area_number ,s.parent_uqid 
,s.wikidataid ,s.level_ ,s.subunit
,NULLIF(s.su_a3,'-99') ,NULLIF(s.iso_a2,'-99') ,NULLIF(s.iso_n3,'-99')
,s.continent ,s.region_un ,s.subregion ,s.region_wb 
,s.geom ,sdo_geom.sdo_mbr(s.geom))
/

