REM strava_pkg.sql
set echo on timi on 
spool strava_pkg.lst
clear screen
rollback;
REM connect strava/strava@oracle_pdb

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

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TYPE polyline_point AS OBJECT (
    latitude  NUMBER,
    longitude NUMBER
);
/

CREATE OR REPLACE TYPE polyline_point_table AS TABLE OF polyline_point;
/
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE strava_pkg as 

FUNCTION decode_polyline
(p_polyline IN VARCHAR2
) RETURN polyline_point_table PIPELINED;

FUNCTION polyline_to_sdo 
(p_polyline IN VARCHAR2
) RETURN SDO_GEOMETRY;

PROCEDURE activity_area_hsearch
(p_activity_id INTEGER
,p_area_code   my_areas.area_code%TYPE DEFAULT NULL
,p_area_number my_areas.area_number%TYPE DEFAULT NULL
,p_query_type VARCHAR2 DEFAULT 'P'
,p_level INTEGER DEFAULT 0
);

PROCEDURE activity_area_search
(p_activity_id INTEGER
);

FUNCTION getClobDocument
(p_directory IN VARCHAR2
,p_filename  IN VARCHAR2
,p_charset   IN VARCHAR2 DEFAULT NULL
) RETURN  CLOB DETERMINISTIC;

FUNCTION make_point 
(longitude in number
,latitude  in number
) RETURN sdo_geometry DETERMINISTIC;

FUNCTION name_hierarchy_fn
(p_area_code   my_areas.area_code%TYPE DEFAULT NULL
,p_area_number my_areas.area_number%TYPE DEFAULT NULL
,p_type VARCHAR2 DEFAULT 'C' /*(C)umulative, (R)oot*/
) RETURN CLOB DETERMINISTIC;

PROCEDURE name_hierarchy_txtidx
(p_rowid in rowid
,p_dataout IN OUT NOCOPY CLOB
);

end strava_pkg;
/
show errors
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE body strava_pkg as 
k_module  CONSTANT VARCHAR2(64 CHAR) := $$PLSQL_UNIT;
k_wgs84   CONSTANT INTEGER := 4326;
----------------------------------------------------------------------------------------------------
FUNCTION decode_polyline (
    p_polyline IN VARCHAR2
) RETURN polyline_point_table PIPELINED
IS
    l_index               PLS_INTEGER := 1;
    l_polyline_len        PLS_INTEGER := LENGTH(p_polyline);
    l_latitude            NUMBER := 0;
    l_longitude           NUMBER := 0;
    l_result              INTEGER;
    l_shift               INTEGER;
    l_policyline_onechar  INTEGER;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'decode_polyline');
    WHILE l_index <= l_polyline_len LOOP
        -- Decode latitude
        l_result := 0; 
		l_shift := 0;
        LOOP
            l_policyline_onechar := ASCII(SUBSTR(p_polyline, l_index, 1)) - 63;
            l_index := l_index + 1;
            l_result := l_result + BITAND(l_policyline_onechar,31) * POWER(2,l_shift);
            l_shift := l_shift + 5;
            EXIT WHEN l_policyline_onechar < 32;
        END LOOP;
        IF BITAND(l_result,1)=1 THEN l_result := -(l_result/2); ELSE l_result := l_result/2; END IF;
        l_latitude := l_latitude + l_result;

        -- Decode longitude
        l_result := 0; l_shift := 0;
        LOOP
            l_policyline_onechar := ASCII(SUBSTR(p_polyline, l_index, 1)) - 63;
            l_index := l_index + 1;
            l_result := l_result + BITAND(l_policyline_onechar,31) * POWER(2,l_shift);
            l_shift := l_shift + 5;
            EXIT WHEN l_policyline_onechar < 32;
        END LOOP;
        IF BITAND(l_result,1)=1 THEN l_result := -(l_result/2); ELSE l_result := l_result/2; END IF;
        l_longitude := l_longitude + l_result;

        PIPE ROW (polyline_point(l_latitude/100000, l_longitude/100000));
    END LOOP;

    RETURN;
END decode_polyline;
----------------------------------------------------------------------------------------------------
FUNCTION polyline_to_sdo (
    p_polyline IN VARCHAR2
) RETURN SDO_GEOMETRY
IS
    l_poly_points polyline_point_table;
    l_coords SDO_ORDINATE_ARRAY := SDO_ORDINATE_ARRAY();
    l_geom   SDO_GEOMETRY;
BEGIN
    SELECT CAST(COLLECT(VALUE(p)) AS polyline_point_table)
    INTO l_poly_points
    FROM TABLE(strava_pkg.decode_polyline(p_polyline)) p;

    FOR i IN 1..l_poly_points.COUNT LOOP
        l_coords.EXTEND(2);
        l_coords(l_coords.COUNT-1) := l_poly_points(i).longitude;
        l_coords(l_coords.COUNT)   := l_poly_points(i).latitude;
    END LOOP;

    l_geom := SDO_GEOMETRY(
        2002,  -- 2D line
        k_wgs84,  -- WGS84
        NULL,
        SDO_ELEM_INFO_ARRAY(1,2,1),
        l_coords
    );

    RETURN l_geom;
END polyline_to_sdo;
----------------------------------------------------------------------------------------------------
PROCEDURE activity_area_hsearch
(p_activity_id INTEGER
,p_area_code   my_areas.area_code%TYPE DEFAULT NULL
,p_area_number my_areas.area_number%TYPE DEFAULT NULL
,p_query_type VARCHAR2 DEFAULT 'P'
,p_level INTEGER DEFAULT 0
) IS
  l_t0 timestamp; 
  l_t1 timestamp;
  l_secs NUMBER;
  l_num_rows NUMBER;
  l_pad VARCHAR2(20 CHAR);

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'activity_area_hsearch:'||p_area_code||'-'||p_area_number||','||p_query_type);

  l_pad := lpad('.',p_level,'.');
  dbms_output.put_line(l_pad||'Searching '||p_activity_id||':'||p_area_code||'-'||p_area_number);
  l_t0 := SYSTIMESTAMP;
  
  FOR i IN(
   SELECT m.*
   ,      CASE WHEN m.geom       IS NOT NULL AND a.geom IS NOT NULL THEN sdo_geom.sdo_length(SDO_GEOM.sdo_intersection(m.geom,a.geom,5), unit=>'unit=km') 
		  END geom_length
   --,      (SELECT MIN(m2.area_level) FROM my_areas m2 WHERE m2.parent_area_code = m.area_code AND m2.parent_area_number = m.area_number) min_child_level
   FROM   my_areas m
   ,      activities a
   WHERE  (  (p_query_type = 'P' AND parent_area_code = p_area_code AND parent_area_number = p_area_number) 
          OR (p_query_type = 'A' AND area_code        = p_area_code AND area_number        = p_area_number)
		  OR (p_query_type = 'A' AND p_area_number IS NULL          AND area_code          = p_area_code)
          OR (p_area_code IS NULL AND p_area_number IS NULL AND parent_area_code IS NULL AND parent_area_number IS NULL)
		  )
   AND    a.activity_id = p_activity_id
   and    SDO_ANYINTERACT(m.geom, a.geom) = 'TRUE'
   and    SDO_ANYINTERACT(m.mbr, a.mbr) = 'TRUE'
   --and    SDO_GEOM.RELATE(a.mbr,'anyinteract',m.mbr) = 'TRUE'
   --and    SDO_GEOM.RELATE(a.geom,'anyinteract',m.geom) = 'TRUE'
  ) LOOP
    dbms_output.put_line(l_pad||'Found '||i.area_code||'-'||i.area_number||':'||i.name||','||TO_CHAR(i.geom_length,'9990.999')||' km');
    IF (i.area_level>0 OR i.num_children IS NULL) AND (i.matchable > 0 OR i.num_children > 0) THEN
	  BEGIN
        INSERT INTO activity_areas
        (activity_id, area_code, area_number, geom_length)
        VALUES
        (p_activity_id, i.area_code, i.area_number, i.geom_length);
	  EXCEPTION
	    WHEN dup_val_on_index THEN
		  UPDATE activity_areas
		  SET    geom_length = i.geom_length
		  WHERE  activity_id = p_activity_id
		  AND    area_code = i.area_code
		  AND    area_number = i.area_number;
      END;
    END IF;
  
    IF i.num_children > 0 THEN
      strava_pkg.activity_area_hsearch(p_activity_id, i.area_code, i.area_number, 'P', p_level+1);
    END IF;
  END LOOP;

  l_t1 := SYSTIMESTAMP;
  l_secs := 60*extract(minute from l_t1-l_t0)+extract(second from l_t1-l_t0);
  dbms_output.put_line(l_pad||'Done '||p_activity_id||':'||p_area_code||'-'||p_area_number||':'||TO_CHAR(l_secs,'9990.999')||' secs).');

  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);
END activity_area_hsearch;
----------------------------------------------------------------------------------------------------
PROCEDURE activity_area_search
(p_activity_id INTEGER
) IS
  l_t0 timestamp; 
  l_t1 timestamp;
  l_secs NUMBER;
  l_num_rows NUMBER := 0;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'activity_area_search');

  dbms_output.put_line('Searching '||p_activity_id);
  l_t0 := SYSTIMESTAMP;
  
  FOR i IN(
   SELECT m.*
   ,      CASE WHEN m.geom       IS NOT NULL AND a.geom IS NOT NULL       THEN sdo_geom.sdo_length(SDO_GEOM.sdo_intersection(m.geom,a.geom,5), unit=>'unit=km') 
		  END geom_length
   FROM   my_areas m
   ,      activities a
   WHERE  a.activity_id = p_activity_id
   and    SDO_ANYINTERACT(m.geom, a.geom) = 'TRUE'
   and    SDO_ANYINTERACT(m.mbr, a.mbr) = 'TRUE'
  ) LOOP
    dbms_output.put_line('Found '||i.area_code||'-'||i.area_number||':'||i.name||','||TO_CHAR(i.geom_length,'9990.999')||' km');
	l_num_rows := l_num_rows + 1;
	BEGIN
      INSERT INTO activity_areas
      (activity_id, area_code, area_number, geom_length)
      VALUES
      (p_activity_id, i.area_code, i.area_number, i.geom_length);
	EXCEPTION WHEN dup_val_on_index THEN
	  UPDATE activity_areas
	  SET    geom_length = i.geom_length
	  WHERE  activity_id = p_activity_id
	  AND    area_code = i.area_code
	  AND    area_number = i.area_number;
    END;
  END LOOP;

  l_t1 := SYSTIMESTAMP;
  l_secs := 60*extract(minute from l_t1-l_t0)+extract(second from l_t1-l_t0);
  dbms_output.put_line('Done '||p_activity_id||':'||l_num_rows||' areas:'||TO_CHAR(l_secs,'9990.999')||' secs).');

  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);
END activity_area_search;
----------------------------------------------------------------------------------------------------
FUNCTION getClobDocument
(p_directory IN VARCHAR2
,p_filename  IN VARCHAR2
,p_charset   IN VARCHAR2 DEFAULT NULL
) RETURN CLOB DETERMINISTIC is
  v_filename      VARCHAR2(128 CHAR);
  v_directory     VARCHAR2(128 CHAR);
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

  l_module        VARCHAR2(64 CHAR);
  l_action        VARCHAR2(64 CHAR);
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
FUNCTION make_point 
(longitude in number
,latitude  in number
) RETURN sdo_geometry DETERMINISTIC is
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
begin
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'make_point');

  if longitude is not null and latitude is not null then
    return
      sdo_geometry (
        2001, k_wgs84,
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
FUNCTION name_hierarchy_fn
(p_area_code   my_areas.area_code%TYPE DEFAULT NULL
,p_area_number my_areas.area_number%TYPE DEFAULT NULL
,p_type VARCHAR2 DEFAULT 'C' /*(C)umulative, (R)oot*/
) RETURN CLOB DETERMINISTIC is
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);

  l_name_hierarchy CLOB;
  l_last_name my_areas.name%TYPE := '';
  l_count INTEGER := 0;
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'name_hierarchy_fn');
								  
  FOR i IN (
    SELECT area_code, area_number, name, matchable
    FROM   my_areas m
    START WITH area_code = p_area_code AND area_number = p_area_number
    CONNECT BY NOCYCLE prior m.parent_area_code   = m.area_code
                   AND prior m.parent_area_number = m.area_number
  ) LOOP
    IF i.matchable >= 1 THEN
      l_count := l_count + 1;
	  --dbms_output.put_line(l_count||':'||i.name||'='||l_last_name);
	  IF l_count > 1 AND p_type = 'C' THEN
	    IF i.name != l_last_name THEN --supress repeated names
          l_name_hierarchy := l_name_hierarchy ||', '|| i.name;
        END IF;
	  ELSE
        l_name_hierarchy := i.name;
	  END IF;
      l_last_name := i.name;
	END IF;
  END LOOP;
  --dbms_output.put_line(p_dataout);
  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);
  RETURN l_name_hierarchy;
END name_hierarchy_fn;
----------------------------------------------------------------------------------------------------
PROCEDURE name_hierarchy_txtidx
(p_rowid in rowid
,p_dataout IN OUT NOCOPY CLOB
) IS
  l_last_name my_areas.name%TYPE := '';
  l_count INTEGER := 0;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module
                                   ,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'name_hierarchy_txtidx');
								  
  FOR i IN (
    SELECT area_code, area_number, name, matchable
    FROM   my_areas m
    START WITH rowid = p_rowid
    CONNECT BY NOCYCLE prior m.parent_area_code   = m.area_code
                   AND prior m.parent_area_number = m.area_number
  ) LOOP
    IF i.matchable >= 1 THEN
      --dbms_output.put_line(i.name);
      l_count := l_count + 1;
	  IF l_count > 1 THEN
	    IF i.name != l_last_name THEN --supress repeated names
          p_dataout := p_dataout ||', '|| i.name;
        END IF;
	  ELSE
        p_dataout := i.name;
	  END IF;
      --dbms_lob.writeappend(p_dataout, length(i.name), i.name);
      l_last_name := i.name;
    END IF;
  END LOOP;
  --dbms_output.put_line(p_dataout);
  dbms_application_info.set_module(module_name=>l_module
                                  ,action_name=>l_action);
END name_hierarchy_txtidx;
----------------------------------------------------------------------------------------------------
END strava_pkg;
/
show errors
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
spool off