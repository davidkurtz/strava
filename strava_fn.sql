REM strava_fn.sql
rollback;
connect strava/strava@oracle_pdb

insert into user_sdo_geom_metadata (table_name,column_name,diminfo,srid)
values ( 
  'ACTIVITIES' , 
  'STRAVA_FN.MAKE_POINT(LNG,LAT)',
  sdo_dim_array(
    sdo_dim_element('Longitude',-180,180,0.05), 
    sdo_dim_element('Latgitude',-90,90,0.05)
  ),
  4326
);
commit;

----------------------------------------------------------------------------------------------------
create or replace package strava_fn as 
function geom_length
(p_geom1 mdsys.sdo_geometry, p_geom2 mdsys.sdo_geometry
,p_geom3 mdsys.sdo_geometry, p_geom4 mdsys.sdo_geometry
,p_tol number default 0.0005
) return  NUMBER;
end strava_fn;
/
show errors
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
create or replace package body strava_fn as 
k_module  CONSTANT VARCHAR2(48) := $$PLSQL_UNIT;
----------------------------------------------------------------------------------------------------
function geom_length
(p_geom1 mdsys.sdo_geometry, p_geom2 mdsys.sdo_geometry 
,p_geom3 mdsys.sdo_geometry, p_geom4 mdsys.sdo_geometry 
,p_tol number default 0.0005
) return NUMBER IS
  l_len    NUMBER;
  l_module VARCHAR2(64);
  l_action VARCHAR2(64);
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'geom_length.1');
  IF p_geom1 IS NOT NULL and p_geom2 IS NOT NULL THEN
    l_len := sdo_geom.sdo_length(SDO_GEOM.sdo_intersection(p_geom1,p_geom2,p_tol), unit=>'unit=km');
  END IF;
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'geom_length.2');
  IF p_geom3 IS NOT NULL and p_geom4 IS NOT NULL AND l_len IS NULL THEN
    l_len := sdo_geom.sdo_length(SDO_GEOM.sdo_intersection(p_geom3,p_geom4,p_tol), unit=>'unit=km');
  END IF;
  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);
  RETURN l_len;
END geom_length;  
----------------------------------------------------------------------------------------------------
end strava_fn;
/
show errors
----------------------------------------------------------------------------------------------------
