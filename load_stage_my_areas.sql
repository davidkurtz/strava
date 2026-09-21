REM load_stage_my_areas.sql
set serveroutput on echo on

----------------------------------------------------------------------------------------------------
--identify parent area in my_areas qwert
----------------------------------------------------------------------------------------------------
clear screen
set serveroutput on
DECLARE
  e_general_error EXCEPTION;
PROCEDURE area_hsearch
(p_searchfor_area_code   stage_my_areas.area_code%TYPE
,p_searchfor_area_number stage_my_areas.area_number%TYPE
,p_searchfrom_code        my_areas.area_code%TYPE DEFAULT NULL
,p_searchfrom_number      my_areas.area_number%TYPE DEFAULT NULL
,p_query_type VARCHAR2 DEFAULT 'A'
,p_level INTEGER DEFAULT 0
) IS
  l_t0 timestamp; 
  l_t1 timestamp;
  l_secs NUMBER;
  l_num_rows NUMBER;
  l_pad VARCHAR2(20 CHAR) := '';
BEGIN
  l_pad := lpad('.',p_level,'.');
  l_t0 := SYSTIMESTAMP;
  
  IF p_level >4 then
    RAISE_APPLICATION_ERROR(-20000,'Recurrsion level '||p_level);
  ELSE
    dbms_output.put_line('Searching '||p_searchfor_area_code||'-'||p_searchfor_area_number
	        ||'. '||p_query_type||':'||p_searchfrom_code||'-'||p_searchfrom_number);

  END IF;
  
  FOR i IN(
   WITH x AS (
   SELECT m.area_code, m.area_number, m.name
   ,      new.area_code new_area_code, new.area_number new_area_number, new.name new_name, new.area new_area
   ,      CASE WHEN m.geom  IS NOT NULL AND new.geom IS NOT NULL THEN c 
		  END intersect_area
   FROM   my_areas m
   ,      stage_my_areas new
   WHERE  (  (p_query_type = 'C' AND m.parent_area_code = p_searchfrom_code AND m.parent_area_number = p_searchfrom_number) 
          OR (p_query_type = 'A' AND m.area_code        = p_searchfrom_code AND m.area_number        = p_searchfrom_number)
		  --OR (p_query_type = 'A' AND p_area_number IS NULL          AND m.area_code          = p_area_code)
          --OR (p_area_code IS NULL AND p_area_number IS NULL AND parent_area_code IS NULL AND parent_area_number IS NULL)
		  )
   AND    new.area_code = p_searchfor_area_code 
   AND    new.area_number = p_searchfor_area_number
   --and    sdo_geom.sdo_intersection(m.mbr,new.mbr,1) IS NOT NULL
   --and    sdo_geom.sdo_intersection(m.geom,new.geom,1) IS NOT NULL
   and    SDO_ANYINTERACT(m.geom, new.geom)
   and    SDO_ANYINTERACT(m.mbr, new.mbr) 
   --and    sdo_geom.RELATE(m.mbr ,'mask=covers',new.mbr ,0.001) 
   --and    sdo_geom.RELATE(m.geom,'mask=covers',new.geom,0.001) 
   --and     m.area_level <7
   and m.rowid != new.rowid
   )
   SELECT * FROM x 
   --WHERE intersect_area/new_area>=.9
   ORDER BY intersect_area desc nulls last fetch first 1 rows only
  ) LOOP
    IF i.intersect_area/i.new_area >= .99 
    OR (i.intersect_area/i.new_area >= .9 AND i.new_area - i.intersect_area < 1) THEN
      dbms_output.put_line(l_pad||'Found '||i.area_code||'-'||i.area_number
	                            ||':'||i.name
		  	 	 			    ||', new area '||i.new_area||' km^2'
			 				    ||', intersection area '||i.intersect_area||' km^2 ('||100*i.intersect_area/i.new_area||'%)'
							    );

	  IF i.area_code = p_searchfor_area_code AND i.area_number = p_searchfor_area_number then
	    dbms_output.put_line('Same');
	  ELSE
	    dbms_output.put_line('Updating '||i.area_code||'-'||i.area_number
		            ||' is a parent of '||p_searchfor_area_code||'-'||p_searchfor_area_number);
  	    UPDATE stage_my_areas
	    SET    parent_area_code = i.area_code
	    ,      parent_area_number = i.area_number
	    WHERE  area_code = p_searchfor_area_code 
        AND    area_number = p_searchfor_area_number;
   	    area_hsearch(p_searchfor_area_code, p_searchfor_area_number, i.area_code, i.area_number, 'C', p_level+1);
	  END IF;
	ELSE
      dbms_output.put_line(l_pad||'Not Matched '||i.area_code||'-'||i.area_number
	                            ||':'||i.name
		  	 	 			    ||', new area '||i.new_area||' km^2'
			 				    ||', intersection area '||i.intersect_area||' km^2 ('||100*i.intersect_area/i.new_area||'%)'
							    );
	END IF;
  END LOOP;

  l_t1 := SYSTIMESTAMP;
  l_secs := 60*extract(minute FROM l_t1-l_t0)+extract(second FROM l_t1-l_t0);
  --dbms_output.put_line(l_pad||'Done '||p_searchfor_area_code||'-'||p_searchfor_area_number||':'||TO_CHAR(l_secs,'9990.999')||' secs).');
END area_hsearch;
  ----------------------------------------------------------------------------------------------------
BEGIN
  FOR i IN (
    SELECT s.* --, a.*
    FROM stage_my_areas s
        LEFT OUTER JOIN my_areas a ON a.area_Code = s.parent_area_code AND a.area_number = s.parent_area_number
    WHERE 1=1
    AND (a.num_children > 0 OR s.parent_area_code IS NULL)
    --and s.name = 'Erkenbrechtsweiler'
	--OR s.parent_area_code IN('STAT','SOVC')
    --FETCH FIRST 500 ROWS ONLY
  ) LOOP
    area_hsearch(i.area_code, i.area_number, i.parent_area_code, i.parent_area_number, 'C', 0);
	COMMIT;
  END LOOP;
END;
/


select * from stage_my_areas;
COMMIT
/
----------------------------------------------------------------------------------------------------
-- verify area match 
----------------------------------------------------------------------------------------------------
select /*+LEADING(m)*/ m.area_code,m.area_number, m.name, a.name
,      sdo_anyinteract(m.mbr,a.mbr) mbr_interact
,      sdo_anyinteract(m.geom,a.geom) geom_interact
,      sdo_geom.RELATE(m.geom ,'determine',a.geom ,0.001) relationship
,      sdo_geom.sdo_area(m.geom, unit=>'unit=sq_km') staging_km_sq
,      sdo_geom.sdo_area(sdo_geom.sdo_intersection(m.geom,a.geom,1), unit=>'unit=sq_km') intersect_km_sq    
from stage_my_areas m, my_areas a
where 1=1
and a.area_code = m.parent_area_code
and a.area_number = m.parent_area_number
order by 1,2
fetch first 50 rows only
/
----------------------------------------------------------------------------------------------------
-- merge staged areas into areas table
----------------------------------------------------------------------------------------------------
--DELETE FROM my_areas where area_code = 'AONB';
MERGE INTO my_areas u 
USING (select * from stage_my_areas order by area_level) s 
ON (s.area_code = u.area_code AND s.area_number = u.area_number)
WHEN MATCHED THEN UPDATE 
SET u.area_level = s.area_level
, u.parent_area_code = s.parent_area_code 
, u.parent_area_number = s.parent_area_number
, u.name = s.name
, u.suffix = s.suffix
, u.matchable = s.matchable
, u.geom = s.geom
, u.mbr = s.mbr
, u.num_pts = s.num_pts
, u.num_children = null
WHEN NOT MATCHED THEN INSERT 
(area_code, area_number, area_level, parent_area_code, parent_area_number, name, suffix, matchable
, geom, mbr, num_pts, num_children)
VALUES
(s.area_code, s.area_number, s.area_level, s.parent_area_code, s.parent_area_number, s.name, s.suffix, s.matchable
, s.geom, s.mbr, s.num_pts, NULL)
/
select * from my_areas
where last_updated IS NULL or last_updated > sysdate-1
order by last_updated desc nulls first
/

----------------------------------------------------------------------------------------------------
--mark activities from recalculation
----------------------------------------------------------------------------------------------------
MERGE INTO activities u
USING (
select DISTINCT a.activity_id, a.name, a.start_date_utc, a.processing_status
, a.last_updated activity_last_updated
, ma.last_updated area_last_updated
from activities a
  INNER JOIN activity_areas aa ON a.activity_id = aa.activity_id
  INNER JOIN my_areas ma ON ma.area_code =aa.area_code and ma.area_number = aa.area_number
where a.last_updated < ma.last_updated
and ma.last_updated > sysdate -7
and a.processing_status > 3
and a.processing_status < 9
) s
ON (s.activity_id = u.activity_id)
WHEN MATCHED THEN UPDATE
SET u.processing_status = 3
/

select *
from activities
where last_updated > SYSDATE-1
and start_date_local > sysdate-1
order by last_updated desc
/
