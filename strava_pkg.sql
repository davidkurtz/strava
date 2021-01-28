rollback;
connect strava/strava@oracle_pdb

insert into user_sdo_geom_metadata (table_name,column_name,diminfo,srid)
values ( 
  'ACTIVITIES' , 
  'STRAVA_PKG.MAKE_POINT(LNG,LAT)',
  sdo_dim_array(
    sdo_dim_element('Longitude',-180,180,0.05), 
    sdo_dim_element('Latgitude',-90,90,0.05)
  ),
  4326
);
commit;

----------------------------------------------------------------------------------------------------
-- strava_pkg.sql
----------------------------------------------------------------------------------------------------
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
create or replace package strava_pkg as 
procedure create_activity_segs
(p_activity_id NUMBER);
function getClobDocument
(p_directory IN VARCHAR2
,p_filename  IN VARCHAR2
,p_charset   IN VARCHAR2 DEFAULT NULL
) return         CLOB deterministic;
procedure load_activity
(p_activity_id NUMBER);
function make_point 
(longitude in number
,latitude  in number)
return sdo_geometry deterministic;
end strava_pkg;
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
----------------------------------------------------------------------------------------------------
create or replace package body strava_pkg as 
k_module      CONSTANT VARCHAR2(48) := $$PLSQL_UNIT;
----------------------------------------------------------------------------------------------------
procedure create_activity_segs
(p_activity_id NUMBER) is
  l_module VARCHAR2(64);
  l_action VARCHAR2(64);

  l_num_rows NUMBER;
  l_t0 timestamp; 
  l_t1 timestamp; 
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'create_activity_segs');

  l_t0 := SYSTIMESTAMP;

  delete from activity_segs 
  WHERE  activity_id = p_activity_id;

  l_t1 := SYSTIMESTAMP;
  l_num_rows := sql%rowcount;

  IF l_num_rows > 0 THEN
    dbms_output.put_line('Activity '||p_activity_id||': '||l_num_rows||' rows deleted ('
                                    ||TO_CHAR(extract(second from l_t1-l_t0),'990.999')||' secs).');
    l_t0 := l_t1;
  END IF;

INSERT INTO activity_segs (activity_id, area_code3, number3, geom_length)
WITH a AS (
SELECT a.activity_id, g.area_code3, g.number3
,      strava_fn.geom_length(g.geom, a.geom, g.geom_27700, a.geom_27700) geom_length
FROM   activities a
,      my_areas g
WHERE  a.activity_id = p_activity_id
and    SDO_GEOM.RELATE(g.mbr,'anyinteract',a.mbr,1) = 'TRUE'
and not exists(
  select 'x' from activity_segs s 
  where s.activity_id = p_activity_id
--and   s.area_code3 = g.area_code3
--and   s.number3 = g.number3
  )
)
SELECT activity_id, area_code3, number3, geom_length
From   a
Where  geom_length > 0;
l_num_rows := sql%rowcount;
l_t1 := SYSTIMESTAMP;

IF l_num_rows > 0 THEN
  commit;
  dbms_output.put_line('Activity '||p_activity_id||': '||l_num_rows||' rows inserted ('
                                  ||TO_CHAR(extract(second from l_t1-l_t0),'990.999')||' secs).');
  l_t0 := l_t1;
ELSE
  dbms_output.put_line('Activity '||p_activity_id||': Nothing to do!');
END IF;

  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);

END create_activity_segs;
----------------------------------------------------------------------------------------------------
function getClobDocument
(p_directory IN VARCHAR2
,p_filename  IN VARCHAR2
,p_charset   IN VARCHAR2 DEFAULT NULL
) return        CLOB deterministic
is
  l_module VARCHAR2(64);
  l_action VARCHAR2(64);

  v_filename      VARCHAR2(128);
  v_directory     VARCHAR2(128);
  v_file          bfile;
  v_unzipped      blob := empty_blob();

  v_Content       CLOB := ' ';
  v_src_offset    number := 1 ;
  v_dst_offset    number := 1 ;
  v_charset_id    number := 0;
  v_lang_ctx      number := DBMS_LOB.default_lang_ctx;
  v_warning       number;

  e_22288 EXCEPTION; --file or LOB operation FILEOPEN failed
  PRAGMA EXCEPTION_INIT(e_22288, -22288);
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'getClobDocument');

  IF p_charset IS NOT NULL THEN
    v_charset_id := NLS_CHARSET_ID(p_charset);
  END IF;

  v_filename  := REGEXP_SUBSTR(p_filename,'[^\/]+',1,2);
  v_directory := REGEXP_SUBSTR(p_filename,'[^\/]+',1,1);

  IF v_directory IS NOT NULL and v_filename IS NULL THEN
    v_filename := v_directory;
    v_directory := '';
  END IF;

  IF p_directory IS NOT NULL THEN
    v_directory := p_directory;
  END IF;

  v_File := bfilename(UPPER(v_directory),v_filename);

  BEGIN
    DBMS_LOB.fileopen(v_File, DBMS_LOB.file_readonly);
  exception 
    when VALUE_ERROR OR e_22288 then
      dbms_output.put_line('Can''t open:'||v_directory||'/'||v_filename||' - '||v_dst_offset||' bytes');
      v_content := '';
      dbms_application_info.set_module(module_name=>l_module
                                      ,action_name=>l_action);
      return v_content;
  END;

  IF v_filename LIKE '%.gz' THEN
    v_unzipped := utl_compress.lz_uncompress(v_file);
    dbms_lob.converttoclob(
      dest_lob     => v_content,
      src_blob     => v_unzipped,
      amount       => DBMS_LOB.LOBMAXSIZE, 
      dest_offset  => v_dst_offset,
      src_offset   => v_src_offset,
      blob_csid    => dbms_lob.default_csid,
      lang_context => v_lang_ctx,
      warning      => v_warning);
  ELSE --ELSIF v_filename LIKE '%.g__' THEN
    DBMS_LOB.LOADCLOBFROMFILE(v_Content, 
      Src_bfile    => v_File,
      amount       => DBMS_LOB.LOBMAXSIZE, 
      src_offset   => v_src_offset, 
      dest_offset  => v_dst_offset,
      bfile_csid   => v_charset_id, 
      lang_context => v_lang_ctx,
      warning => v_warning);
  END IF;

  dbms_output.put_line(v_directory||'/'||v_filename||' - '||v_dst_offset||' bytes');
  DBMS_LOB.fileclose(v_File);

  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);

  return v_Content;
exception when others then
  dbms_output.put_line(v_directory||'/'||v_filename||' - '||v_dst_offset||' bytes');
  DBMS_LOB.fileclose(v_File);
  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);
  raise;
end getClobDocument;
----------------------------------------------------------------------------------------------------
procedure load_activity
(p_activity_id NUMBER) IS
  l_module VARCHAR2(64);
  l_action VARCHAR2(64);

  l_num_rows INTEGER;
  l_num_pts INTEGER;
  l_gpx CLOB;
  
  l_xmlns0 VARCHAR2(64);
  l_xmlns1 VARCHAR2(64);

  e_13034 EXCEPTION; --Invalid data in the SDO_ORDINATE_ARRAY in SDO_GEOMETRY object
  e_29877 EXCEPTION; --failed in the execution of the ODCIINDEXUPDATE routine
  PRAGMA EXCEPTION_INIT(e_13034, -13034);
  PRAGMA EXCEPTION_INIT(e_29877, -29877);
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'load_activity');
  dbms_output.put_line('Loading Activity: '||p_activity_id);
  
  BEGIN
    SELECT strava_pkg.getClobDocument('ACTIVITIES',filename)
    INTO   l_gpx
    FROM   activities 
    WHERE  activity_id = p_activity_id
    AND    filename IS NOT NULL;
    l_num_rows := SQL%rowcount;
  EXCEPTION
    WHEN no_data_found THEN
	  l_num_rows := 0;
	  dbms_output.put_line('Cannot find activity '||p_activity_id);
  END;
  
IF l_num_rows > 0 THEN
  UPDATE activities
  SET    gpx = XMLTYPE(l_gpx), geom = null, geom_27700 = null, num_pts = 0, xmlns = NULL
  WHERE  activity_id = p_activity_id
  RETURNING extractvalue(gpx,'/gpx/@creator', 'xmlns="http://www.topografix.com/GPX/1/0"') 
  ,         extractvalue(gpx,'/gpx/@creator', 'xmlns="http://www.topografix.com/GPX/1/1"') 
  INTO      l_xmlns0, l_xmlns1;
  l_num_rows := SQL%rowcount;
END IF;
  
IF l_num_rows > 0 AND l_xmlns1 IS NOT NULL THEN
  dbms_output.put_line('xmlns 1='||l_xmlns1);
  BEGIN
    UPDATE activities a
    SET geom = mdsys.sdo_geometry(2002,4326,null,mdsys.sdo_elem_info_array(1,2,1),
    cast(multiset(
      select CASE n.rn WHEN 1 THEN pt.lng WHEN 2 THEN pt.lat END ord
      from (
        SELECT rownum rn
        ,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'trkpt/@lon')) as lng
        ,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'trkpt/@lat')) as lat
        FROM   TABLE(XMLSEQUENCE(extract(a.gpx,'/gpx/trk/trkseg/trkpt', 'xmlns="http://www.topografix.com/GPX/1/1"'))) t
        ) pt,
        (select 1 rn from dual union all select 2 from dual) n
	    order by pt.rn, n.rn
      ) AS mdsys.sdo_ordinate_array))
    , xmlns = 'xmlns="http://www.topografix.com/GPX/1/1"'
    WHERE  a.gpx IS NOT NULL
    And    activity_id = p_activity_id;
    l_num_rows := SQL%rowcount;
  EXCEPTION
    WHEN e_13034 OR e_29877 THEN 
	  dbms_output.put_line('Exception:'||sqlerrm);
	  l_num_rows := 0;
  END;
ELSIF l_num_pts = 0 AND l_xmlns0 IS NOT NULL THEN
  dbms_output.put_line('xmlns 0='||l_xmlns0);
  UPDATE activities a
  SET    geom = mdsys.sdo_geometry(2002,4326,null,mdsys.sdo_elem_info_array(1,2,1),
  cast(multiset(
    select CASE n.rn WHEN 1 THEN pt.lng WHEN 2 THEN pt.lat END ord
    from (
      SELECT rownum rn
      ,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'trkpt/@lon')) as lng
      ,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'trkpt/@lat')) as lat
      FROM   TABLE(XMLSEQUENCE(extract(a.gpx,'/gpx/trk/trkseg/trkpt', 'xmlns="http://www.topografix.com/GPX/1/0"'))) t
      ) pt,
      (select 1 rn from dual union all select 2 from dual) n
	  order by pt.rn, n.rn
    ) AS mdsys.sdo_ordinate_array))
  , xmlns = 'xmlns="http://www.topografix.com/GPX/1/0"'
  WHERE  a.gpx IS NOT NULL
  and    (a.num_pts = 0 OR a.geom IS NULL)
  And    activity_id = p_activity_id;
  l_num_rows := SQL%rowcount;
END IF;

IF l_num_rows > 0 THEN
  BEGIN
    UPDATE activities 
    SET    geom = sdo_util.simplify(geom,1)
    WHERE  geom IS NOT NULL
    And    activity_id = p_activity_id;
    l_num_rows := SQL%rowcount;
  EXCEPTION
    WHEN e_13034 THEN 
	  dbms_output.put_line('Exception:'||sqlerrm);
  END;
END IF;

IF l_num_rows > 0 THEN
  UPDATE activities 
  SET    num_pts = SDO_UTIL.GETNUMVERTICES(geom)
  ,      geom_27700 = sdo_cs.transform(geom,27700)
  ,      mbr = sdo_geom.sdo_mbr(geom)
  WHERE  geom IS NOT NULL
  And    activity_id = p_activity_id
  RETURNING num_pts INTO l_num_pts;
  dbms_output.put_line('Activity ID:'||p_activity_id||', '||l_num_pts||' points');
  l_num_rows := SQL%rowcount;
END IF;

  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);

END load_activity;
----------------------------------------------------------------------------------------------------
function make_point 
(longitude in number
,latitude  in number)
return sdo_geometry deterministic is
  l_module VARCHAR2(64);
  l_action VARCHAR2(64);
begin
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'make_point');

  if longitude is not null and latitude is not null then
    return
      sdo_geometry (
        2001, 4326,
        sdo_point_type (longitude, latitude, null),
        null, null
      );
  else
    return null;
  end if;

  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);
end make_point;
----------------------------------------------------------------------------------------------------
END strava_pkg;
/
show errors
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
