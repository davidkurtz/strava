REM load_user_areas.sql
clear screen
set echo on
spool load_user_areas.lst


--area staging table - one row per geometry
DROP TABLE stage_my_areas PURGE;
CREATE TABLE stage_my_areas (
    AREA_CODE VARCHAR2(4 CHAR) NOT NULL , 
	AREA_NUMBER NUMBER(*,0) NOT NULL , 
	UQID VARCHAR2(20 CHAR) NOT NULL , 
 	AREA_LEVEL NUMBER(*,0), 
	PARENT_AREA_CODE VARCHAR2(4 CHAR), 
	PARENT_AREA_NUMBER NUMBER(*,0), 
	PARENT_UQID VARCHAR2(20 CHAR), 
	NAME VARCHAR2(100 CHAR), 
	MATCHABLE NUMBER(*,0) DEFAULT 1, 
--
    GEOM MDSYS.SDO_GEOMETRY ,
	MBR MDSYS.SDO_GEOMETRY , 
	AREA NUMBER,
	NUM_PTS NUMBER(*,0)    
);

ALTER TABLE stage_my_areas ADD CONSTRAINT stage_my_areas_pk PRIMARY KEY (area_code, area_number);
ALTER TABLE stage_my_areas ADD CONSTRAINT stage_my_areas_pk2 UNIQUE (uqid);

INSERT INTO USER_SDO_GEOM_METADATA (
    TABLE_NAME,
    COLUMN_NAME,
    DIMINFO,
    SRID
) VALUES (
    'STAGE_GEO_DATA',
    'GEOM',
    SDO_DIM_ARRAY(
        SDO_DIM_ELEMENT('Longitude', -180, 180, 0.005),
        SDO_DIM_ELEMENT('Latitude',  -90,  90, 0.005)
    ),
    4326
);

INSERT INTO USER_SDO_GEOM_METADATA (
    TABLE_NAME,
    COLUMN_NAME,
    DIMINFO,
    SRID
) VALUES (
    'STAGE_MY_AREAS',
    'GEOM',
    SDO_DIM_ARRAY(
        SDO_DIM_ELEMENT('Longitude', -180, 180, 0.005),
        SDO_DIM_ELEMENT('Latitude',  -90,  90, 0.005)
    ),
    4326
);

DROP INDEX stage_geo_data_sidx
/

INSERT INTO my_area_codes VALUES ('USER','User Defined Areas',9);
COMMIT;

delete from stage_my_areas;
----------------------------------------------------------------------------------------------------
--France, Col du Galibier
----------------------------------------------------------------------------------------------------
INSERT INTO stage_my_areas (area_code, area_number, uqid, name, geom)
VALUES (
  'USER',2507301,'FRA2507301','Col du Galibier',
  SDO_GEOMETRY(
    2003,              -- 2003 = polygon / 2D line type
    4326,              -- SRID (WGS84)
    NULL, 
    SDO_ELEM_INFO_ARRAY(1,1003,1),  -- simple polygon
    SDO_ORDINATE_ARRAY(
	  6.4090000,45.0644500,
	  6.4070000,45.0644500,
	  6.4070000,45.0636000,
	  6.4090000,45.0636000,
	  6.4090000,45.0644500
    )
  )
);
/*
----------------------------------------------------------------------------------------------------
--France, Col de la Bonette
----------------------------------------------------------------------------------------------------
INSERT INTO stage_my_areas (area_code, area_number, uqid, name, geom)
VALUES (
  'USER',2500401,'FRA2500401','Col de la Cime de la Bonette',
  SDO_GEOMETRY(
    2003,              -- 2003 = polygon / 2D line type
    4326,              -- SRID (WGS84)
    NULL, 
    SDO_ELEM_INFO_ARRAY(1,1003,1),  -- simple polygon
    SDO_ORDINATE_ARRAY(
	  6.8085000,44.3270000,
	  6.8065000,44.3270000,
	  6.8065000,44.3260000,
	  6.8085000,44.3260000,
	  6.8085000,44.3270000
    )
  )
);
----------------------------------------------------------------------------------------------------
--France, Col de la Cime de la Bonette
----------------------------------------------------------------------------------------------------
INSERT INTO stage_my_areas (area_code, area_number, uqid, name, geom)
VALUES (
  'USER',2500402,'FRA2500402','Col de la Cime de la Bonette',
  SDO_GEOMETRY(
    2003,              -- 2003 = polygon / 2D line type
    4326,              -- SRID (WGS84)
    NULL, 
    SDO_ELEM_INFO_ARRAY(1,1003,1),  -- simple polygon
    SDO_ORDINATE_ARRAY(
	  6.8098000,44.3218000,
	  6.8040000,44.3218000,
	  6.8040000,44.3200000,
	  6.8098000,44.3200000,
	  6.8098000,44.3218000
    )
  )
);
----------------------------------------------------------------------------------------------------
--France, Mt. Ventoux
----------------------------------------------------------------------------------------------------
INSERT INTO stage_my_areas (area_code, area_number, uqid, name, geom)
VALUES (
  'USER',2502601,'FRA2502601','Mont Ventoux',
  SDO_GEOMETRY(
    2003,              -- 2003 = polygon / 2D line type
    4326,              -- SRID (WGS84)
    NULL, 
    SDO_ELEM_INFO_ARRAY(1,1003,1),  -- simple polygon
    SDO_ORDINATE_ARRAY(
	  5.2798080,44.1746000,
	  5.2768200,44.1746000,
	  5.2768200,44.1728000,
	  5.2798080,44.1728000,
	  5.2798080,44.1746000
    )
  )
);
----------------------------------------------------------------------------------------------------
-- Ireland, Glencree, Wicklow
----------------------------------------------------------------------------------------------------
INSERT INTO stage_my_areas (area_code, area_number, uqid, name, geom)
VALUES (
  'USER',250003,'IRL25003','Glencree',
  SDO_GEOMETRY(
    2003,              -- 2003 = polygon / 2D line type
    4326,              -- SRID (WGS84)
    NULL, 
    SDO_ELEM_INFO_ARRAY(1,1003,1),  -- simple polygon
    SDO_ORDINATE_ARRAY(
	  -6.29115200,53.19850000,    -- lon, lat
	  -6.29115200,53.20079000,
	  -6.29366400,53.20079000,
	  -6.29366400,53.19850000,
	  -6.29115200,53.19850000
    )
  )
);
----------------------------------------------------------------------------------------------------
--Ireland, Sally Gap
----------------------------------------------------------------------------------------------------
delete from stage_my_areas;
INSERT INTO stage_my_areas (area_code, area_number, uqid, name, geom)
VALUES (
  'USER',250001,'IRL25001','Sally Gap',
  SDO_GEOMETRY(
    2003,              -- 2003 = polygon / 2D line type
    4326,              -- SRID (WGS84)
    NULL, 
    SDO_ELEM_INFO_ARRAY(1,1003,1),  -- simple polygon
    SDO_ORDINATE_ARRAY(
      -6.312492, 53.137857,    -- lon, lat
      -6.312026, 53.137510,
      -6.311592, 53.137667,
      -6.312000, 53.137999,
	  -6.312492, 53.137857
    )
  )
);
----------------------------------------------------------------------------------------------------
-- Ireland, Wicklow Gap
----------------------------------------------------------------------------------------------------
INSERT INTO stage_my_areas (area_code, area_number, uqid, name, geom)
VALUES (
  'USER',250002,'IRL25002','Wicklow Gap',
  SDO_GEOMETRY(
    2003,              -- 2003 = polygon / 2D line type
    4326,              -- SRID (WGS84)
    NULL, 
    SDO_ELEM_INFO_ARRAY(1,1003,1),  -- simple polygon
    SDO_ORDINATE_ARRAY(
	  -6.3971760,53.0412810,    -- lon, lat
	  -6.3974390,53.0422290,
	  -6.3988340,53.0417380,
	  -6.3971760,53.0412810
    )
  )
);
----------------------------------------------------------------------------------------------------
--Italy
----------------------------------------------------------------------------------------------------
--select * from my_areas where uqid like 'ITA%';
INSERT INTO stage_my_areas (area_code, area_number, uqid, name, geom)
VALUES (
  'USER',380001,'IT380001','Passo dello Stelvio',
  SDO_GEOMETRY(
    2003,              -- 2003 = polygon / 2D line type
    4326,              -- SRID (WGS84)
    NULL, 
    SDO_ELEM_INFO_ARRAY(1,1003,1),  -- simple polygon
    SDO_ORDINATE_ARRAY(
	  10.45334600,46.52799600,    -- lon, lat
	  10.45467100,46.52889600,
	  10.45239700,46.53002200,
	  10.45127000,46.52906300,
      10.45334600,46.52799600
    )
  )
);
----------------------------------------------------------------------------------------------------
-- UK, Swains Lane, London
----------------------------------------------------------------------------------------------------
delete from stage_my_areas;
INSERT INTO stage_my_areas (area_code, area_number, uqid, name, parent_area_code, parent_area_number, geom)
VALUES (
  'USER',5063201,'UKLBO5063201','Swains Lane','LBO', 50632,
  SDO_GEOMETRY(
    2003,  -- two-dimensional polygon
    4326,
    NULL,
    SDO_ELEM_INFO_ARRAY(1,1003,1), -- one polygon (exterior polygon ring counter-clockwise)
    SDO_ORDINATE_ARRAY(-0.14770468632509, 51.569613039632 --Swains World
                      ,-0.14832964102552, 51.569407978151 
                      ,-0.14674177328872, 51.567090552402 
                      ,-0.14592101733016, 51.567080548869 
                      ,-0.14770468632509, 51.569613039632 
                      )
    )
);
update stage_my_areas
set name = 'Swain''s Lane'
where name = 'Swains Lane';
*/
----------------------------------------------------------------------------------------------------
*/
UPDATE stage_my_areas
SET    mbr = sdo_geom.sdo_mbr(geom)
,      num_pts = SDO_UTIL.GETNUMVERTICES(geom)
,      area = sdo_geom.sdo_area(geom, unit=>'unit=sq_km')
,      area_level = 9
/
select * from stage_my_areas;
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
  
  IF p_level >6 then
    RAISE_APPLICATION_ERROR(-20000,'Recurrsion level '||p_level);
  ELSE
    dbms_output.put_line('Searching '||p_searchfor_area_code||'-'||p_searchfor_area_number
	        ||'. '||p_query_type||':'||p_searchfrom_code||'-'||p_searchfrom_number);

  END IF;
  
  FOR i IN(
   WITH x AS (
   SELECT m.area_code, m.area_number, m.name
   ,      new.area_code new_area_code, new.area_number new_area_number, new.name new_name, new.area new_area
   ,      CASE WHEN m.geom  IS NOT NULL AND new.geom IS NOT NULL THEN sdo_geom.sdo_area(SDO_GEOM.sdo_intersection(m.geom,new.geom,0.001), unit=>'unit=sq_km') 
		  END geom_area
   FROM   my_areas m
   ,      stage_my_areas new
   WHERE  (  (p_query_type = 'C' AND m.parent_area_code = p_searchfrom_code AND m.parent_area_number = p_searchfrom_number) 
          OR (p_query_type = 'A' AND m.area_code        = p_searchfrom_code AND m.area_number        = p_searchfrom_number)
		  --OR (p_query_type = 'A' AND p_area_number IS NULL          AND m.area_code          = p_area_code)
          OR (p_searchfrom_code IS NULL AND p_searchfrom_number IS NULL AND m.parent_area_code IS NULL AND m.parent_area_number IS NULL)
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
   WHERE geom_area/new_area>=.9
   ORDER BY geom_area desc nulls last fetch first 1 rows only
  ) LOOP
    IF i.geom_area/i.new_area >= .99 THEN
      dbms_output.put_line(l_pad||'Found '||i.area_code||'-'||i.area_number
	                            ||':'||i.name
		  	 	 			    ||', area '||i.new_area||' km^2'
			 				    ||', intersection area '||i.geom_area||' km^2 ('||100*i.geom_area/i.new_area||'%)'
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
		  	 	 			    ||', area '||i.new_area||' km^2'
			 				    ||', intersection area '||i.geom_area||' km^2 ('||100*i.geom_area/i.new_area||'%)'
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
    SELECT * FROM stage_my_areas 
	WHERE area_code = 'USER'
    --AND parent_area_number IS NULL
	--FETCH FIRST 10 ROWS ONLY
  ) LOOP
    area_hsearch(i.area_code, i.area_number, i.parent_area_code, i.parent_area_number, 'A', 0);
	COMMIT;
  END LOOP;
END;
/
----------------------------------------------------------------------------------------------------
-- verify area match 
----------------------------------------------------------------------------------------------------
select m.name, a.name
,      sdo_anyinteract(m.mbr,a.mbr) mbr_interact
,      sdo_anyinteract(m.geom,a.geom) geom_interact
,      sdo_relate(m.geom,a.geom,'OVERLAPBDYINTERSECT') overlapping
,      sdo_relate(m.geom,a.geom,'TOUCH') touching
,      sdo_relate(m.geom,a.geom,'INSIDE') inside
,      sdo_geom.sdo_area(m.geom, unit=>'unit=sq_km') staging_km_sq
,      sdo_geom.sdo_area(sdo_geom.sdo_intersection(m.geom,a.geom,1), unit=>'unit=sq_km') intersect_km_sq    
from stage_my_areas m, my_areas a
where 1=1
--and a.area_code = 'SOVC' and a.area_number = 372
and m.area_code = 'USER'
--and m.area_number = 15008
and a.area_code = m.parent_area_code
and a.area_number = m.parent_area_number
fetch first 10 rows only
/
----------------------------------------------------------------------------------------------------
-- merge staged areas into areas table
----------------------------------------------------------------------------------------------------
MERGE INTO my_areas u 
USING (select * from stage_my_areas order by area_level) s 
ON (s.area_code = u.area_code AND s.area_number = u.area_number)
WHEN MATCHED THEN UPDATE 
SET u.area_level = s.area_level
, u.parent_area_code = s.parent_area_code 
, u.parent_area_number = s.parent_area_number
, u.name = s.name
, u.matchable = s.matchable
, u.geom = s.geom
, u.mbr = s.mbr
, u.num_pts = s.num_pts
, u.num_children = null
WHEN NOT MATCHED THEN INSERT 
(area_code, area_number, uqid, area_level, parent_area_code, parent_area_number, name, matchable
, geom, mbr, num_pts, num_children)
VALUES
(s.area_code, s.area_number, s.uqid, s.area_level, s.parent_area_code, s.parent_area_number, s.name, s.matchable
, s.geom, s.mbr, s.num_pts, NULL)
/
SELECT * FROM MY_AREAS WHERE area_code = 'USER';
----------------------------------------------------------------------------------------------------
-- correct parent uqid 
----------------------------------------------------------------------------------------------------
merge into my_areas u
using (
select c.area_level, c.area_code, c.area_number, p.uqid parent_uqid
from my_areas c
  inner join my_areas p
    on p.area_code = c.parent_area_code
    and p.area_number = c.parent_area_number
where c.parent_uqid IS NULL 
and c.parent_area_code IS NOT NULL
order by c.area_level
) s
ON (s.area_code = u.area_code AND s.area_number = u.area_number)
WHEN MATCHED THEN UPDATE 
SET u.parent_uqid = s.parent_uqid
/
----------------------------------------------------------------------------------------------------
--correct count of number of children
----------------------------------------------------------------------------------------------------
merge into my_areas u
using (
select p.area_code, p.area_number, p.name, p.num_children, count(c.area_number) child_count
from my_areas p
  left outer join my_areas c
    on p.area_code = c.parent_area_code
    and p.area_number = c.parent_area_number
where 1=1
--and c.num_children IS NULL
group by p.area_code, p.area_number, p.name, p.num_children
having count(c.area_number) != NVL(p.num_children,0)
) s
ON (s.area_code = u.area_code AND s.area_number = u.area_number)
WHEN MATCHED THEN UPDATE 
SET u.num_children = s.child_count
/
----------------------------------------------------------------------------------------------------
-- mark all acitivities potentially affected by  ew user area 
----------------------------------------------------------------------------------------------------
update activities a
set processing_status = 3
where activity_id IN(
  select DISTINCT aa.activity_id
  from stage_my_areas sma
  , activity_areas aa
  where aa.area_code = sma.parent_area_code
  and aa.area_number = sma.parent_area_number)
and a.processing_status > 3
/
----------------------------------------------------------------------------------------------------
--mark activities for full recalculation - but this may hit too many
----------------------------------------------------------------------------------------------------
MERGE INTO activities u
USING (
select a.activity_id, a.name, a.start_date_utc, a.processing_status, a.last_updated activity_last_updated
, MAX(ma.last_updated) area_last_updated
from activities a
,    activity_areas aa
,    my_areas ma
where a.activity_id = aa.activity_id
and ma.area_code =aa.area_code 
and ma.area_number = aa.area_number
and a.last_updated < ma.last_updated
and a.processing_status > 3
group by a.activity_id, a.name, a.start_date_utc, a.processing_status, a.last_updated
) s
ON (s.activity_id = u.activity_id)
WHEN MATCHED THEN UPDATE
SET u.processing_status = 3
/
--EXECUTE dbms_Scheduler.run_job('STRAVA.CREATE_ACTIVITY_HSEARCH_UPD_ALL_JOB',FALSE) /*refresh all activity areas-can take time*/;
----------------------------------------------------------------------------------------------------
--mark for recalculation of just area list - optional
----------------------------------------------------------------------------------------------------
MERGE INTO activities u
USING (
select a.activity_id, a.name, a.start_date_utc, a.processing_status
, a.last_updated act_last_updated
, ma.last_updated areas_last_updated
from activities a
,    activity_areas aa
,    my_areas ma
where a.activity_id = aa.activity_id
and ma.area_code =aa.area_code 
and ma.area_number = aa.area_number
and a.last_updated < ma.last_updated
and a.processing_status >4
) s
ON (s.activity_id = u.activity_id)
WHEN MATCHED THEN UPDATE
SET u.processing_status = 4
/

--EXECUTE dbms_Scheduler.run_job('STRAVA.ACTIVITY_AREA_LIST_UPD_ALL_JOB',FALSE) /*this runs a job to create the update jobs*/; 
--EXECUTE dbms_Scheduler.run_job('STRAVA.UPDATE_STRAVA_ACTIVTY_JOB') /*in current session*/;
--EXECUTE dbms_Scheduler.run_job('STRAVA.UPDATE_STRAVA_ACTIVTY_JOB',FALSE);