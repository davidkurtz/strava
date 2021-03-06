REM my_areas_ddl.sql

CREATE TABLE my_area_codes
(area_code varchar2(4) not null
,description varchar2(30) not null
,area_level number not null
,constraint my_area_codes_pk primary key (area_code)
);

CREATE TABLE my_areas
(area_Code varchar2(4) not null
,area_number integer not null
,uqid varchar2(20) not null
,wikidataid varchar2(20)
,area_level integer not null /*root=0*/
,parent_area_code varchar2(4)
,parent_area_number integer
,parent_uqid varchar2(20)
,name varchar2(40)
,suffix varchar2(20)
,iso_code3 varchar2(3)
,iso_code2 varchar2(5)
,iso_number integer
,num_children integer
,matchable integer
,continent varchar2(30)	
,region_un varchar2(30)	
,subregion varchar2(30)	
,region_wb varchar2(30)
,geom mdsys.sdo_geometry
,geom_27700 mdsys.sdo_geometry
,mbr mdsys.sdo_geometry
,constraint my_areas_pk primary key (area_code, area_number)
,constraint my_areas_uqid unique (uqid)
,constraint my_areas_rfk_area_code foreign key (parent_area_code, parent_area_number) references my_areas (area_code, area_number)
,constraint my_areas_rfk_uqid foreign key (parent_uqid) references my_areas (uqid)
,constraint my_areas_fk_area_code foreign key (area_code) references my_area_codes (area_code)
)
/

alter table my_areas modify matchable default 1;
Alter table my_areas add constraint my_areas_uq_iso_code3 unique (iso_code3);
Create index my_areas_rfk_uqid on my_areas(parent_uqid);
Create index my_areas_rfk_area_code on my_areas (parent_area_code, parent_area_number);

create synonym my_Areas2 for my_areas;