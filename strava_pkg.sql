REM strava_pkg.sql
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
rollback;
create or replace package strava_pkg as 

function getClobDocument
(p_directory IN VARCHAR2
,p_filename  IN VARCHAR2
,p_charset   IN VARCHAR2 DEFAULT NULL
) return         CLOB deterministic;

procedure load_activity
(p_activity_id INTEGER);

function make_point 
(longitude in number
,latitude  in number)
return sdo_geometry deterministic;

procedure activity_area_search
(p_activity_id INTEGER
,p_area_code   my_areas2.area_code%TYPE DEFAULT NULL
,p_area_number my_areas2.area_number%TYPE DEFAULT NULL
,p_level INTEGER DEFAULT 0
);

end strava_pkg;
/
show errors
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
create or replace package body strava_pkg as 
k_module      CONSTANT VARCHAR2(48) := $$PLSQL_UNIT;
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

  IF v_directory IS NOT NULL and v_filename IS NULL THEN /*if only one parameters then it is actually a filename*/
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
(p_activity_id INTEGER) IS
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
procedure activity_area_search
(p_activity_id INTEGER
,p_area_code   my_areas2.area_code%TYPE DEFAULT NULL
,p_area_number my_areas2.area_number%TYPE DEFAULT NULL
,p_level INTEGER DEFAULT 0
,p_query_type VARCHAR2(1) DEFAULT 'P'
) IS
  l_module VARCHAR2(64);
  l_action VARCHAR2(64);

  l_t0 timestamp; 
  l_t1 timestamp;
  l_secs NUMBER;
  l_num_rows NUMBER;
  l_pad varchar2(20);
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'activity_area_search:'||p_area_code||'-'||p_area_number||','||p_query_type);

  l_pad := lpad('.',p_level,'.');
  dbms_output.put_line(l_pad||'Searching '||p_activity_id||':'||p_area_code||'-'||p_area_number);
  l_t0 := SYSTIMESTAMP;
  
  FOR i IN(
   SELECT m.*
   ,      CASE WHEN m.geom_27700 IS NOT NULL THEN sdo_geom.sdo_length(SDO_GEOM.sdo_intersection(m.geom_27700,a.geom_27700,5), unit=>'unit=km') 
               WHEN m.geom       IS NOT NULL THEN sdo_geom.sdo_length(SDO_GEOM.sdo_intersection(m.geom,a.geom,5), unit=>'unit=km') 
		  END geom_length
   ,      (SELECT MIN(m2.area_level) FROM my_areas2 m2 WHERE m2.parent_area_Code = m.area_code AND m2.parent_area_number = m.area_number) min_child_level
   FROM   my_areas2 m
   ,      activities a
   WHERE  (  (p_query_type = 'P' AND parent_area_code = p_area_code AND parent_area_number = p_area_number) 
          OR (p_query_type = 'A' AND area_code        = p_area_code AND area_number        = p_area_number)
		  OR (p_query_type = 'A' AND p_area_number IS NULL          AND area_code          = p_area_code)
          OR (p_area_code IS NULL AND p_area_number IS NULL AND parent_area_code IS NULL AND parent_area_number IS NULL)
		  )
   AND    a.activity_id = p_activity_id
   and    SDO_GEOM.RELATE(a.mbr,'anyinteract',m.mbr) = 'TRUE'
   and    SDO_GEOM.RELATE(a.geom,'anyinteract',m.geom) = 'TRUE'
  ) LOOP
    dbms_output.put_line(l_pad||'Found '||i.area_code||'-'||i.area_number||':'||i.name||','||TO_CHAR(i.geom_length,'9990.999')||' km');
    IF i.area_level>0 OR i.num_children IS NULL THEN
      INSERT INTO activity_areas
      (activity_id, area_code, area_number, geom_length)
      VALUES
      (p_activity_id, i.area_code, i.area_number, i.geom_length);
    END IF;
  
    IF i.num_children > 0 THEN
      strava_pkg.activity_area_search(p_activity_id, i.area_code, i.area_number, p_level+1, 'P');
    END IF;
  END LOOP;

  l_t1 := SYSTIMESTAMP;
  l_secs := 60*extract(minute from l_t1-l_t0)+extract(second from l_t1-l_t0);
  dbms_output.put_line(l_pad||'Done '||p_activity_id||':'||p_area_code||'-'||p_area_number||':'||TO_CHAR(l_secs,'9990.999')||' secs).');

  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);
END activity_area_search;
----------------------------------------------------------------------------------------------------
END strava_pkg;
/
show errors
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
