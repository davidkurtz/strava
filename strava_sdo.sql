REM strava_sdo.sql
set echo on timi on 
spool strava_sdo.lst
clear screen
rollback;

--delete from user_sdo_geom_metadata where table_name = 'ACTIVITIES';
insert into user_sdo_geom_metadata (table_name,column_name,diminfo,srid)
values ( 
  'ACTIVITIES' , 
  'strava_sdo.MAKE_POINT(LNG,LAT)',
  sdo_dim_array(
    sdo_dim_element('Longitude',-180,180,0.05), 
    sdo_dim_element('Latgitude',-90,90,0.05)
  ),
  k_wgs84
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
CREATE OR REPLACE PACKAGE strava_sdo as 

PROCEDURE activity_area_hsearch
(p_activity_id activities.activity_id%TYPE
,p_area_code   my_areas.area_code%TYPE DEFAULT NULL
,p_area_number my_areas.area_number%TYPE DEFAULT NULL
,p_query_type VARCHAR2 DEFAULT 'P'
,p_level INTEGER DEFAULT 0
);

PROCEDURE activity_area_list_upd
(p_activity_id activities.activity_id%TYPE
);

PROCEDURE activity_area_list_upd_all;

PROCEDURE activity_area_search
(p_activity_id activities.activity_id%TYPE
);

PROCEDURE activity_hsearch_upd
(p_activity_id activities.activity_id%TYPE
);

FUNCTION build_sdo_geometry_from_geojson
(p_geom_json IN JSON_OBJECT_T
,p_srid INTEGER DEFAULT 4326
) RETURN MDSYS.SDO_GEOMETRY;

FUNCTION decode_polyline
(p_polyline IN VARCHAR2
) RETURN polyline_point_table PIPELINED;

FUNCTION geom_to_gpx 
(p_geom IN MDSYS.SDO_GEOMETRY
,p_name IN VARCHAR2 DEFAULT NULL
) RETURN XMLTYPE;

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

FUNCTION polyline_to_geom 
(p_polyline IN VARCHAR2
) RETURN SDO_GEOMETRY;

PROCEDURE update_activity_description
(p_activities  IN OUT activities%ROWTYPE
);

end strava_sdo;
/
show errors
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE body strava_sdo as 
----------------------------------------------------------------------------------------------------
k_module     CONSTANT VARCHAR2(64 CHAR) := $$PLSQL_UNIT;
k_creator    CONSTANT VARCHAR2(64 CHAR) := 'GFCStavaPlaceCloud';
k_wgs84      CONSTANT INTEGER := 4326;
k_geom_point CONSTANT INTEGER := 2001;
k_geom_line  CONSTANT INTEGER := 2002;
----------------------------------------------------------------------------------------------------
--special characters
----------------------------------------------------------------------------------------------------
k_ampersand  CONSTANT VARCHAR2(1 CHAR)  := CHR(38);
k_lf         CONSTANT VARCHAR2(1 CHAR)  := CHR(10);
k_spc        CONSTANT VARCHAR2(1 CHAR)  := ' ';
----------------------------------------------------------------------------------------------------
--Activity Statuses
----------------------------------------------------------------------------------------------------
k3_status_stream_loaded       CONSTANT INTEGER := 3;
k4_status_areas_processed     CONSTANT INTEGER := 4;
k5_status_area_list_updated   CONSTANT INTEGER := 5;
k6_status_description_updated CONSTANT INTEGER := 6;
----------------------------------------------------------------------------------------------------
--Exceptions
----------------------------------------------------------------------------------------------------
e_22288 EXCEPTION; --file or LOB operation FILEOPEN failed
PRAGMA EXCEPTION_INIT(e_22288, -22288);
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
  dbms_application_info.read_module(module_name=>l_module, action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module, action_name=>'decode_polyline');
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
        
	IF BITAND(l_result,1)=1 THEN 
	  l_result := -(l_result/2); 
	ELSE 
	  l_result := l_result/2; 
	END IF;
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

    IF BITAND(l_result,1)=1 THEN 
	  l_result := -(l_result/2); 
	ELSE 
	  l_result := l_result/2; 
	END IF;
    l_longitude := l_longitude + l_result;

    PIPE ROW (polyline_point(l_latitude/100000, l_longitude/100000));
  END LOOP;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RETURN;
END decode_polyline;
----------------------------------------------------------------------------------------------------
-- convert strava polyline map to a spatial geometry
----------------------------------------------------------------------------------------------------
FUNCTION polyline_to_geom (
    p_polyline IN VARCHAR2
) RETURN SDO_GEOMETRY
IS
  l_poly_points polyline_point_table;
  l_coords SDO_ORDINATE_ARRAY := SDO_ORDINATE_ARRAY();
  l_geom   SDO_GEOMETRY;
  l_num_points  INTEGER;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module, action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module, action_name=>'decode_polyline');

  SELECT CAST(COLLECT(VALUE(p)) AS polyline_point_table)
  INTO l_poly_points
  FROM TABLE(strava_sdo.decode_polyline(p_polyline)) p;

  FOR i IN 1..l_poly_points.COUNT LOOP
    l_coords.EXTEND(2);
    l_coords(l_coords.COUNT-1) := l_poly_points(i).longitude;
    l_coords(l_coords.COUNT)   := l_poly_points(i).latitude;
  END LOOP;
  
  l_num_points := l_poly_points.COUNT;
  --dbms_output.put_line('polyline:'||l_num_points);

  IF l_num_points > 0 THEN
    l_geom := SDO_GEOMETRY(
          k_geom_line,  -- 2D line
          k_wgs84,  
          NULL,
          SDO_ELEM_INFO_ARRAY(1,2,1),
          l_coords
          );
  END IF;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RETURN l_geom;
END polyline_to_geom;
----------------------------------------------------------------------------------------------------
-- look for activity id that is status k3 and generate new area list and update to status k4
----------------------------------------------------------------------------------------------------
PROCEDURE activity_hsearch_upd
(p_activity_id activities.activity_id%TYPE
) IS
  l_activity_id activities.activity_id%TYPE;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'activity_hsearch_upd');

  SELECT activity_id
  INTO   l_activity_id
  FROM   activities
  WHERE  processing_status = k3_status_stream_loaded
  AND    activity_id = p_activity_id
  FOR UPDATE;
  
  strava_sdo.activity_area_hsearch(l_activity_id);
  
  UPDATE ACTIVITIES
  SET    processing_status = k4_status_areas_processed
  WHERE  activity_id = p_activity_id;

  --update area list column from the generated activity areas
  activity_area_list_upd(p_activity_id);
  
  COMMIT;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION WHEN no_data_found THEN 
  dbms_output.put_line(sqlerrm||'.  Activity '||p_activity_id||' not at status '||k3_status_stream_loaded||'.');
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END activity_hsearch_upd;
----------------------------------------------------------------------------------------------------
-- generate and insert placecloud report in description from area_list
----------------------------------------------------------------------------------------------------
PROCEDURE update_activity_description
(p_activities  IN OUT activities%ROWTYPE
) is
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  

  k_placecloud_header VARCHAR2(16) := '-- PlaceCloud --';
  k_placecloud_footer VARCHAR2(10) := '-- END --';
  --k_placecloud_regexp VARCHAR2(64) := k_placecloud_header||'(\S|.|\s)*'||k_placecloud_footer;
  l_placecloud_pos INTEGER;
  l_placecloud_end INTEGER;
  l_placecloud_rep CLOB;

BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'update_activity_description');
    
  l_placecloud_rep := k_placecloud_header
              ||k_lf||p_activities.area_list
		      ||k_lf||k_placecloud_footer;

  --dbms_output.put_line('New Placecloud report: '||l_placecloud_rep);
  p_activities.description := RTRIM(p_activities.description,k_lf||k_spc);
  p_activities.description := LTRIM(p_activities.description,k_lf||k_spc);
	
  IF p_activities.description IS NULL THEN
    p_activities.description := l_placecloud_rep;
  ELSE
    LOOP
      l_placecloud_pos := NVL(INSTR(p_activities.description,k_placecloud_header,1),0);
  	  --dbms_output.put_line('PlaceCloud Pos:'||l_placecloud_pos);
	  EXIT WHEN l_placecloud_pos <= 0;
	  l_placecloud_end := INSTR(p_activities.description,k_placecloud_footer,l_placecloud_pos,1);
 	  --dbms_output.put_line('PlaceCloud End:'||l_placecloud_end);
	  IF l_placecloud_end>0 THEN
	    p_activities.description := SUBSTR(p_activities.description,1,l_placecloud_pos-1)
		                          ||SUBSTR(p_activities.description,l_placecloud_end+LENGTH(k_placecloud_footer));
	  ELSE
	    p_activities.description := SUBSTR(p_activities.description,1,l_placecloud_pos-1);
	  END IF;
	END LOOP;    

    p_activities.description := RTRIM(p_activities.description,k_lf||k_spc);
    p_activities.description := LTRIM(p_activities.description,k_lf||k_spc);
	
    IF p_activities.description IS NULL THEN 
	  p_activities.description := l_placecloud_rep;
	ELSE 
      p_activities.description := p_activities.description||k_lf||l_placecloud_rep;
	END IF;
    --DBMS_LOB.writeappend(p_activities.description,LENGTH(l_placecloud_rep),l_placecloud_rep);
  END IF;
  
  --strava_http.print_clob(p_activities.description);
  p_activities.processing_status := k6_status_description_updated;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION WHEN OTHERS then
  dbms_output.put_line('update_activity_description:'||sqlerrm);
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RAISE;
END update_activity_description;
----------------------------------------------------------------------------------------------------
-- generate area list from activities
----------------------------------------------------------------------------------------------------
PROCEDURE activity_area_list_upd
(p_activity_id activities.activity_id%TYPE
) IS
  l_new_area_list activities.area_list%TYPE;
  l_old_area_list activities.area_list%TYPE;
  l_description   activities.description%TYPE;

  e_activity_not_found EXCEPTION;
  k_job_name CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.UPDATE_STRAVA_ACTIVTY_JOB';

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'activity_area_list_upd');

  SELECT area_list, description
  INTO   l_old_area_list, l_description
  FROM   activities
  WHERE  activity_id = p_activity_id
  AND    processing_status = k4_status_areas_processed
  FOR UPDATE OF processing_status;
  
  --New Oracle 26 returning clause on MERGE
  --https://blog.sqlora.com/en/merge-and-dml-returning-clause-in-oracle-23ai/
  --https://connor-mcdonald.com/2025/09/18/merge-in-23ai-so-much-more-than-returning/
  MERGE INTO activities u
  USING (
    SELECT a.activity_id
    ,      listagg(DISTINCT ma.name,', ') within group (order by ma.area_level, ma.name) area_list
    FROM   activities a
      INNER JOIN activity_areas aa on a.activity_id = aa.activity_id
      INNER JOIN my_areas ma on ma.area_code = aa.area_code and ma.area_number = aa.area_number
	  INNER JOIN my_area_codes mac ON mac.area_code = ma.area_code
    WHERE a.activity_id = p_activity_id
	AND a.processing_status = k4_status_areas_processed
	and ma.matchable = 1
    GROUP BY a.activity_id
  ) S 
  ON (s.activity_id = u.activity_id)
  WHEN MATCHED THEN UPDATE 
  SET u.area_list = s.area_list
  RETURNING new area_list
  INTO l_new_area_list;
  
  IF SQL%ROWCOUNT = 0 OR l_new_area_list IS NULL THEN 
    RAISE e_activity_not_found;
  ELSE
    NULL;
    dbms_output.put_line('Updated activity '||p_activity_id||' area_list:'||l_new_area_list);
	dbms_scheduler.run_job(job_name=>k_job_name, use_current_session=>FALSE);
  END IF;

/*----------------------------------------------------------------------------------------------------
  -- do not update the description here because we need check the description has not been changed by 
  -- something else such as WindSock, so need to reread the description in directly before updating it
  ----------------------------------------------------------------------------------------------------
  update_activity_description(l_new_area_list,l_description);
  UPDATE activities
  SET    description = l_description
  ,      processing_status = k5_status_area_list_updated
  WHERE  activity_id = p_activity_id
  AND    processing_status = k4_status_areas_processed;
  
  IF SQL%ROWCOUNT = 0 THEN 
    RAISE e_activity_not_found;
  ELSE
    COMMIT;
	dbms_scheduler.set_attribute(name => k_job_name, attribute => 'START_DATE',value => SYSTIMESTAMP AT TIME ZONE 'UTC');
  END IF;
  dbms_output.put_line('Updated activity '||p_activity_id||' area_list:'||l_new_area_list);
  ----------------------------------------------------------------------------------------------------*/
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN no_data_found THEN 
    dbms_output.put_line(sqlerrm||'.  Activity '||p_activity_id||' not at status '||k4_status_areas_processed||'.');
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  WHEN e_activity_not_found THEN 
    dbms_output.put_line(sqlerrm||'.  Activity area list '||p_activity_id||' not generated.');
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  WHEN OTHERS THEN 
    dbms_output.put_line(sqlerrm||'.  Activity '||p_activity_id||' not updated.');
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END activity_area_list_upd;
----------------------------------------------------------------------------------------------------
PROCEDURE activity_area_list_upd_all 
IS
  l_area_list activities.area_list%TYPE;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
  
  e_activity_not_found EXCEPTION;
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'activity_area_list_upd_all');

  FOR i IN (
    SELECT activity_id
    FROM   activities
    WHERE  processing_status = k4_status_areas_processed
    --FOR UPDATE OF processing_status
  ) LOOP
    activity_area_list_upd(i.activity_id);
  END LOOP;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION WHEN OTHERS THEN 
  dbms_output.put_line(sqlerrm);
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END activity_area_list_upd_all;
----------------------------------------------------------------------------------------------------
-- do hierarchical spatial search of activity intersecting with areas
----------------------------------------------------------------------------------------------------
PROCEDURE activity_area_hsearch
(p_activity_id activities.activity_id%TYPE
,p_area_code   my_areas.area_code%TYPE 
,p_area_number my_areas.area_number%TYPE 
,p_query_type VARCHAR2 
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
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module
                                  ,action_name=>'activity_area_hsearch:'||p_area_code||'-'||p_area_number||','||p_query_type);

  l_pad := lpad('.',p_level,'.');
  dbms_output.put_line(l_pad||'Searching '||p_activity_id||':'||p_area_code||'-'||p_area_number);
  l_t0 := SYSTIMESTAMP;
  
  FOR i IN(
   SELECT m.*
   ,      CASE WHEN m.geom IS NOT NULL AND a.geom IS NOT NULL THEN sdo_geom.sdo_length(SDO_GEOM.sdo_intersection(m.geom,a.geom,5), unit=>'unit=km') 
		  END geom_length
   FROM   my_areas m
     INNER JOIN my_area_codes mac ON mac.area_code = m.area_code
   ,      activities a
   WHERE  (  (p_query_type = 'P'  AND m.parent_area_code = p_area_code AND m.parent_area_number = p_area_number) 
          OR (p_query_type = 'A'  AND m.area_code        = p_area_code AND m.area_number        = p_area_number)
		  OR (p_query_type = 'A'  AND p_area_number IS NULL            AND m.area_code          = p_area_code)
          OR (p_area_code IS NULL AND p_area_number IS NULL AND m.parent_area_code IS NULL AND m.parent_area_number IS NULL)
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
      strava_sdo.activity_area_hsearch(p_activity_id, i.area_code, i.area_number, 'P', p_level+1);
    END IF;
  END LOOP;

  l_t1 := SYSTIMESTAMP;
  l_secs := 60*extract(minute from l_t1-l_t0)+extract(second from l_t1-l_t0);
  dbms_output.put_line(l_pad||'Done '||p_activity_id||':'||p_area_code||'-'||p_area_number||':'||TO_CHAR(l_secs,'9990.999')||' secs).');

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END activity_area_hsearch;
----------------------------------------------------------------------------------------------------
--perform hierarchical area search for a particular activity, and write results to ACTIVITY_AREAS
----------------------------------------------------------------------------------------------------
PROCEDURE activity_area_search
(p_activity_id activities.activity_id%TYPE
) IS
  l_t0 timestamp; 
  l_t1 timestamp;
  l_secs NUMBER;
  l_num_rows NUMBER := 0;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'activity_area_search');

  dbms_output.put_line('Searching '||p_activity_id);
  l_t0 := SYSTIMESTAMP;
  
  FOR i IN(
   SELECT m.*
   ,      CASE WHEN m.geom IS NOT NULL AND a.geom IS NOT NULL THEN sdo_geom.sdo_length(SDO_GEOM.sdo_intersection(m.geom,a.geom,5), unit=>'unit=km') 
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

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
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

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'getClobDocument');

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

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  return v_Content;
exception when others then
  dbms_output.put_line(v_directory||'/'||v_filename||' - '||v_dst_offset||' bytes');
  DBMS_LOB.fileclose(v_File);
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  raise;
end getClobDocument;
----------------------------------------------------------------------------------------------------
-- function to return longitude/latitude coordinate as a spatial point
----------------------------------------------------------------------------------------------------
FUNCTION make_point 
(longitude in number
,latitude  in number
) RETURN sdo_geometry DETERMINISTIC is
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
begin
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'make_point');

  if longitude is not null and latitude is not null then
    return
      sdo_geometry (
        k_geom_point, k_wgs84,
        sdo_point_type (longitude, latitude, null),
        null, null
      );
  else
    return null;
  end if;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
end make_point;
----------------------------------------------------------------------------------------------------
-- function to return area hierarchy 
----------------------------------------------------------------------------------------------------
FUNCTION name_hierarchy_fn
(p_area_code   my_areas.area_code%TYPE DEFAULT NULL
,p_area_number my_areas.area_number%TYPE DEFAULT NULL
,p_type VARCHAR2 DEFAULT 'C' /*(C)umulative, (R)oot*, (A)ll/*/
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
    IF i.matchable >= 1 OR p_type = 'A' THEN
      l_count := l_count + 1;
	  --dbms_output.put_line(l_count||':'||i.name||'='||l_last_name);
	  IF p_type = 'R' OR (l_count = 1 AND p_type = 'A') THEN
        l_name_hierarchy := i.name;
	  ELSIF (l_count > 1) AND p_type IN('A','C') THEN
	    IF i.name != l_last_name AND NOT l_last_name like i.name||' %'  THEN --supress repeated names
          l_name_hierarchy := l_name_hierarchy ||', '|| i.name;
        END IF;
	  END IF;
      l_last_name := i.name;
	END IF;
  END LOOP;
  --dbms_output.put_line(p_dataout);
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RETURN l_name_hierarchy;
END name_hierarchy_fn;
----------------------------------------------------------------------------------------------------
-- procedure to return area hierarchy as outbound parameter
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
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'name_hierarchy_txtidx');
								  
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
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END name_hierarchy_txtidx;
----------------------------------------------------------------------------------------------------
-- convert a spatial geometry to a GPX file - no timestamps or altitude
----------------------------------------------------------------------------------------------------
FUNCTION geom_to_gpx 
(p_geom IN MDSYS.SDO_GEOMETRY
,p_name IN VARCHAR2 DEFAULT NULL
) RETURN XMLTYPE IS
  l_gpx       CLOB;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'geom_to_gpx');
  
  DBMS_LOB.CREATETEMPORARY(l_gpx, TRUE);  -- create temporary CLOB

  -- Start GPX document
  DBMS_LOB.APPEND(l_gpx,'<?xml version="1.0" encoding="UTF-8"?>');
  DBMS_LOB.APPEND(l_gpx,'<gpx version="1.1" creator="'||k_creator||'" '||'xmlns="http://www.topografix.com/GPX/1/1">');
  DBMS_LOB.APPEND(l_gpx,'<trk>');
  IF p_name IS NOT NULL THEN
    DBMS_LOB.APPEND(l_gpx,'<name>'||REPLACE(p_name, k_ampersand, k_ampersand||'amp;')||'</name>');
  END IF;
  DBMS_LOB.APPEND(l_gpx,'<trkseg>');

  -- Loop over vertices safely using TABLE(GETVERTICES())
  FOR v IN (
    SELECT * FROM TABLE(
      MDSYS.SDO_UTIL.GETVERTICES(SDO_CS.TRANSFORM(p_geom, k_wgs84) -- transform to WGS84
      )
    )
  ) LOOP
    DBMS_LOB.APPEND(l_gpx,'<trkpt lat="' || v.y || '" lon="' || v.x || '"></trkpt>');
  END LOOP;

  -- Close GPX tags
  DBMS_LOB.APPEND(l_gpx,'</trkseg></trk></gpx>');

  RETURN XMLTYPE(l_gpx);
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END geom_to_gpx;
----------------------------------------------------------------------------------------------------
-- alternative to sdo_util.from_geojson - slower but more robust - use when Oracle function errors
----------------------------------------------------------------------------------------------------
FUNCTION build_sdo_geometry_from_geojson
(p_geom_json IN JSON_OBJECT_T
,p_srid INTEGER 
) RETURN MDSYS.SDO_GEOMETRY
IS
  k_polygon      CONSTANT INTEGER := 2003;
  k_multipolygon CONSTANT INTEGER := 2007;
  l_type       VARCHAR2(30);
  l_sdo_gtype  INTEGER;
  l_coords     JSON_ARRAY_T;
  l_polygon    JSON_ARRAY_T;
  l_ring       JSON_ARRAY_T;
  l_point      JSON_ARRAY_T;

  l_ordinates   SDO_ORDINATE_ARRAY := SDO_ORDINATE_ARRAY();
  l_elem_info   SDO_ELEM_INFO_ARRAY := SDO_ELEM_INFO_ARRAY();
  l_offset     NUMBER := 1;
  l_poly_count NUMBER := 0;
  l_ring_count NUMBER;
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'build_sdo_geometry_from_geojson');

  l_type := p_geom_json.get_string('type');

  IF l_type = 'Polygon' THEN
    l_coords := p_geom_json.get_array('coordinates');
    l_poly_count := 1;
  ELSIF l_type = 'MultiPolygon' THEN
    l_coords := p_geom_json.get_array('coordinates');
    l_poly_count := l_coords.get_size;
  ELSE
    RAISE_APPLICATION_ERROR(-20001,'Unsupported geometry type: '||l_type);
  END IF;

  -- Loop over each polygon
  FOR i IN 0 .. l_poly_count - 1 LOOP
    IF l_type = 'Polygon' THEN
      l_polygon := l_coords;
      l_sdo_gtype := k_polygon;
    ELSE
      l_polygon := TREAT(l_coords.get(i) AS JSON_ARRAY_T);
      l_sdo_gtype := k_multipolygon;
    END IF;

    -- Loop over each ring
    FOR j IN 0 .. l_polygon.get_size - 1 LOOP
      l_ring := TREAT(l_polygon.get(j) AS JSON_ARRAY_T);
      l_ring_count := l_ring.get_size;

      -- Append ordinates
      FOR k IN 0 .. l_ring_count - 1 LOOP
        l_point := TREAT(l_ring.get(k) AS JSON_ARRAY_T);
        l_ordinates.EXTEND(2);
        l_ordinates(l_ordinates.COUNT-1) := l_point.get_Number(0);
        l_ordinates(l_ordinates.COUNT)   := l_point.get_Number(1);
      END LOOP;

      -- Add element info for this ring
      l_elem_info.EXTEND(3);
      l_elem_info(l_elem_info.COUNT-2) := l_offset;
      l_elem_info(l_elem_info.COUNT-1) := 1003; -- exterior ring
      l_elem_info(l_elem_info.COUNT)   := 1;

      l_offset := l_ordinates.COUNT + 1;
    END LOOP;
  END LOOP;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RETURN SDO_GEOMETRY(
           l_sdo_gtype, -- 2D Polygon/MultiPolygon
           p_srid,
           NULL, --point_type
           l_elem_info,
           l_ordinates
           );
END build_sdo_geometry_from_geojson;
----------------------------------------------------------------------------------------------------
END strava_sdo; 
/

show errors
--drop package strava.strava_pkg;
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
spool off