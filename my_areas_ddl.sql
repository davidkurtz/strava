REM my_areas_ddl.sql

CREATE TABLE my_area_codes
(area_code varchar2(4) not null
,description varchar2(60) not null
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
,name varchar2(60)
,suffix varchar2(20)
,iso_code3 varchar2(3)
,iso_code2 varchar2(5)
,iso_number integer
,num_children integer
,matchable integer default 1
,continent varchar2(30)	
,region_un varchar2(30)	
,subregion varchar2(30)	
,region_wb varchar2(30)
,geom mdsys.sdo_geometry
,geom_27700 mdsys.sdo_geometry
,mbr mdsys.sdo_geometry
,num_pts integer
,constraint my_areas_pk primary key (area_code, area_number)
,constraint my_areas_uqid unique (uqid) --alternative unique identifier
,constraint my_areas_uq_iso_code3 unique (iso_code3); --standard country code unique identifies one country row
,constraint my_areas_rfk_area_code foreign key (parent_area_code, parent_area_number) references my_areas (area_code, area_number) --linked list validation
,constraint my_areas_rfk_uqid foreign key (parent_uqid) references my_areas (uqid) --linked list validation
,constraint my_areas_fk_area_code foreign key (area_code) references my_area_codes (area_code)
,constraint my_areas_check_parent_area_code CHECK (area_code != parent_area_code OR area_number != parent_area_number) --linked list validation-not self parent
,constraint my_areas_check_parent_uqid CHECK (uqid != parent_uqid) --not self parent
,constraint my_areas_check_matchable CHECK (matchable IN(0,1))
)
/

alter table my_areas add num_pts integer;
alter table my_areas modify matchable default 1;
Alter table my_areas add constraint my_areas_uq_iso_code3 unique (iso_code3);
Alter table my_areas add constraint my_areas_check_parent_area_code CHECK (area_code != parent_area_code OR area_number != parent_area_number);
Alter table my_areas add constraint my_areas_check_parent_uqid CHECK (uqid != parent_uqid);
Alter table my_areas add constraint my_areas_check_matchable CHECK (matchable IN(0,1));

alter table my_areas drop column name_heirarchy;
alter table my_areas add name_heirarchy VARCHAR(4000) /*as (strava_pkg.name_heirarchy_fn(area_code,area_number))*/;

Create index my_areas_rfk_uqid on my_areas(parent_uqid);
Create index my_areas_rfk_area_code on my_areas (parent_area_code, parent_area_number);

create synonym my_Areas2 for my_areas;

CREATE TABLE STRAVA.ACTIVITY_AREAS
(ACTIVITY_ID NUMBER NOT NULL
,AREA_CODE   VARCHAR2(4) NOT NULL
,AREA_NUMBER NUMBER NOT NULL
,GEOM_LENGTH NUMBER
,CONSTRAINT ACTIVITY_AREAS_PK PRIMARY KEY (ACTIVITY_ID, AREA_CODE, AREA_NUMBER)
,CONSTRAINT ACTIVITY_AREAS_FK FOREIGN KEY (ACTIVITY_ID) REFERENCES STRAVA.ACTIVITIES (ACTIVITY_ID)
,CONSTRAINT ACTIVITY_AREAS_FK2 FOREIGN KEY (AREA_CODE, AREA_NUMBER) REFERENCES STRAVA.MY_AREAS (AREA_CODE, AREA_NUMBER)
);

