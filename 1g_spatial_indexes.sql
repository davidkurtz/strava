REM 1g_spatial_indexes.sql
DROP INDEX my_areas_mbr FORCE;
DROP INDEX my_areas_geom FORCE;
DROP INDEX my_areas_geom_27700 FORCE;
delete from user_sdo_geom_metadata where table_name = 'MY_GEOMETRIES';
commit;

delete from user_sdo_geom_metadata where table_name IN('ACTIVITIES','MY_AREAS');
commit;

insert into user_sdo_geom_metadata (table_name,column_name,diminfo,srid)
values ( 
  'ACTIVITIES' , 'GEOM_27700',
  sdo_dim_array(
    sdo_dim_element('Easting',-1000000,1500000,0.05), 
    sdo_dim_element('Northing', -500000,2000000,0.05)),
  27700);
insert into user_sdo_geom_metadata (table_name,column_name,diminfo,srid)
values ( 
  'ACTIVITIES' , 'GEOM',
  sdo_dim_array(
    sdo_dim_element('Longitude',-180,180,0.05), 
    sdo_dim_element('Latgitude',-90,90,0.05)),
  4326);
insert into user_sdo_geom_metadata (table_name,column_name,diminfo,srid)
values ( 
  'ACTIVITIES' , 'MBR',
  sdo_dim_array(
    sdo_dim_element('Longitude',-180,180,0.05), 
    sdo_dim_element('Latgitude',-90,90,0.05)),
  4326);
commit;

insert into user_sdo_geom_metadata (table_name,column_name,diminfo,srid)
values ( 
  'MY_AREAS' , 'GEOM_27700',
  sdo_dim_array(
    sdo_dim_element('Easting',-1000000,1500000,0.05), 
    sdo_dim_element('Northing', -500000,2000000,0.05)),
  27700);
insert into user_sdo_geom_metadata (table_name,column_name,diminfo,srid)
values ( 
  'MY_AREAS' , 'GEOM',
  sdo_dim_array(
    sdo_dim_element('Longitude',-180,180,0.05), 
    sdo_dim_element('Latgitude',-90,90,0.05)),
  4326);
insert into user_sdo_geom_metadata (table_name,column_name,diminfo,srid)
values ( 
  'MY_AREAS' , 'MBR',
  sdo_dim_array(
    sdo_dim_element('Longitude',-180,180,0.05), 
    sdo_dim_element('Latgitude',-90,90,0.05)),
  4326);
commit;


DROP INDEX activities_geom FORCE;
DROP INDEX activities_geom_27700 FORCE;
DROP INDEX activities_mbr FORCE;

DROP INDEX my_areas_geom FORCE;
DROP INDEX my_areas_geom_27700 FORCE;
DROP INDEX my_areas_mbr FORCE;

CREATE INDEX activities_geom ON ACTIVITIES (geom) INDEXTYPE IS MDSYS.SPATIAL_INDEX_v2;
CREATE INDEX activities_geom_27700 ON ACTIVITIES (geom_27700) INDEXTYPE IS MDSYS.SPATIAL_INDEX_v2;
CREATE INDEX activities_mbr ON ACTIVITIES (mbr) INDEXTYPE IS MDSYS.SPATIAL_INDEX_v2;

CREATE INDEX my_areas_geom ON my_areas (geom) INDEXTYPE IS MDSYS.SPATIAL_INDEX_v2;
CREATE INDEX my_areas_geom_27700 ON my_areas (geom_27700) INDEXTYPE IS MDSYS.SPATIAL_INDEX_v2;
CREATE INDEX my_areas_mbr ON my_areas (mbr) INDEXTYPE IS MDSYS.SPATIAL_INDEX_v2;