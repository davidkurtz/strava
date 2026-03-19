REMREM ireland_state_boundaries.sql
set echo on timi on serveroutput on pages 99
clear screen
spool ireland_state_boundaries.lst

delete from stage_my_areas
WHERE area_code = 'SOVC'
and   area_number = 1159320877
/
INSERT INTO stage_my_areas
(area_code, area_number, uqid, name)
VALUES
('SOVC', 1159320877, 'NE1159320877', 'Ireland')
/
commit
/

SELECT DISTINCT t.geom.SDO_SRID FROM my_areas t
WHERE area_code = 'SOVC'
and   area_number = 1159320877
;
SELECT DISTINCT t.geom.SDO_SRID FROM stage_counties t;
SELECT DISTINCT t.geom.SDO_SRID FROM stage_my_areas t;

/*--tried to do it in one step, but too many points
INSERT INTO stage_my_areas
(area_code, area_number, uqid, name, geom)
SELECT 'SOVC', 1159320877, 'NE1159320877', 'Ireland'
--, SDO_AGGR_UNION(SDOAGGRTYPE(geom, 1)) geom
, sdo_aggr.SDO_AGGR_SET_UNION(geom,1) geom
FROM my_areas m
WHERE m.parent_area_code = 'SOVC'
and m.parent_area_number = 1159320877 --ireland
and m.area_code = 'CTY' --county
*/

drop table stage_counties purge
/

create table stage_counties
as select area_code, area_number, name
, SDO_UTIL.RECTIFY_GEOMETRY(geom, 0.005) geom
, 0 seq_num
, 0 area
FROM my_areas m
WHERE m.parent_area_code = 'SOVC'
and m.parent_area_number = 1159320877 --ireland
and m.area_code = 'CTY' --county
/
update stage_counties
set area = sdo_geom.sdo_area(geom, unit=>'unit=sq_km')
/
CREATE INDEX stage_counties_sidx
ON stage_counties(geom)
INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2
/
select area_code, area_number, name, seq_num, area
from stage_counties
order by name
/

spool ireland_state_boundaries.lst append
set serveroutput on
--part 1
DECLARE
  l_tol NUMBER := 0.005;
  l_counter INTEGER := 0;
  l_geom   SDO_GEOMETRY;
  l_area_code1 stage_counties.area_code%TYPE;
  l_area_code2 stage_counties.area_code%TYPE;
  l_area_number1 stage_counties.area_number%TYPE;
  l_area_number2 stage_counties.area_number%TYPE;
  l_name1 stage_counties.name%TYPE;
  l_name2 stage_counties.name%TYPE;
  l_geom1 SDO_GEOMETRY;
  l_geom2 SDO_GEOMETRY;
  l_area number;
  l_area1 number;
  l_area2 number;
  l_distance NUMBER;
BEGIN
  LOOP
    l_counter := l_counter + 1;
    SELECT c1.area_code, c1.area_number, c1.name, c1.geom, c1.area
    ,      c2.area_code, c2.area_number, c2.name, c2.geom, c2.area
	,      SDO_GEOM.SDO_DISTANCE(SDO_GEOM.SDO_CENTROID(c1.geom, l_tol),
                                 SDO_GEOM.SDO_CENTROID(c2.geom, l_tol), l_tol) distance
    INTO   l_area_code1, l_area_number1, l_name1, l_geom1, l_area1
    ,      l_area_code2, l_area_number2, l_name2, l_geom2, l_area2
	,      l_distance
    FROM   stage_counties c1
    ,      stage_counties c2
    WHERE  c1.area_code = c2.area_code
	AND    c1.area_number < c2.area_number
	AND    SDO_ANYINTERACT(c1.geom, c2.geom) = 'TRUE'
	--ORDER BY distance
    FETCH FIRST 1 ROWS ONLY;

    dbms_output.put_line(l_counter||': Merging '||l_name1||' ('||l_area1||'sqKm) with '||l_name2||' ('||l_area2||'sqKm), distance:'||l_distance);
    l_geom := SDO_GEOM.SDO_UNION(l_geom1, l_geom2);      
	l_geom := SDO_UTIL.RECTIFY_GEOMETRY(l_geom, l_tol);
	
	UPDATE stage_counties
	SET    geom = l_geom
	,      area = sdo_geom.sdo_area(l_geom, unit=>'unit=sq_km')
	WHERE  area_code = l_area_code1
	AND    area_number = l_area_number1;
	
	DELETE FROM stage_counties
	WHERE  area_code = l_area_code2
	AND    area_number = l_area_number2;
	
	COMMIT;

	EXIT WHEN l_counter >= 26;
  END LOOP;
EXCEPTION WHEN no_data_found THEN
  dbms_output.put_line('Ended.  Counter='||l_counter);  
END;
/

spool ireland_state_boundaries.lst append
--part 2
DECLARE
  l_tol NUMBER := 0.005;
  l_counter INTEGER := 0;
  l_geom   SDO_GEOMETRY;
  l_area_code1 stage_counties.area_code%TYPE;
  l_area_code2 stage_counties.area_code%TYPE;
  l_area_number1 stage_counties.area_number%TYPE;
  l_area_number2 stage_counties.area_number%TYPE;
  l_name1 stage_counties.name%TYPE;
  l_name2 stage_counties.name%TYPE;
  l_geom1 SDO_GEOMETRY;
  l_geom2 SDO_GEOMETRY;
  l_area number;
  l_area1 number;
  l_area2 number;
  l_distance NUMBER;
BEGIN
  LOOP
    l_counter := l_counter + 1;
    SELECT c1.area_code, c1.area_number, c1.name, c1.geom, c1.area
    ,      c2.area_code, c2.area_number, c2.name, c2.geom, c2.area
	,      SDO_GEOM.SDO_DISTANCE(SDO_GEOM.SDO_CENTROID(c1.geom, l_tol),
                                 SDO_GEOM.SDO_CENTROID(c2.geom, l_tol), l_tol) distance
    INTO   l_area_code1, l_area_number1, l_name1, l_geom1, l_area1
    ,      l_area_code2, l_area_number2, l_name2, l_geom2, l_area2
	,      l_distance
    FROM   stage_counties c1
    ,      stage_counties c2
    WHERE  c1.area_code = c2.area_code
	AND    c1.area_number < c2.area_number
	--AND    SDO_ANYINTERACT(c1.geom, c2.geom) = 'TRUE'
	ORDER BY distance
    FETCH FIRST 1 ROWS ONLY;

    dbms_output.put_line(l_counter||': Merging '||l_name1||' ('||l_area1||'sqKm) with '||l_name2||' ('||l_area2||'sqKm), distance:'||l_distance);
    l_geom := SDO_GEOM.SDO_UNION(l_geom1, l_geom2);      
	l_geom := SDO_UTIL.RECTIFY_GEOMETRY(l_geom, l_tol);
	
	UPDATE stage_counties
	SET    geom = l_geom
	,      area = sdo_geom.sdo_area(l_geom, unit=>'unit=sq_km')
	WHERE  area_code = l_area_code1
	AND    area_number = l_area_number1;
	
	DELETE FROM stage_counties
	WHERE  area_code = l_area_code2
	AND    area_number = l_area_number2;
	
	COMMIT;

	EXIT WHEN l_counter >= 26;
  END LOOP;
EXCEPTION WHEN no_data_found THEN
  dbms_output.put_line('Ended.  Counter='||l_counter);  
END;
/


update stage_counties
set area = sdo_geom.sdo_area(geom, unit=>'unit=sq_km')
/
commit;

select count(*) num_counties, sum(area) total_county_areas
from stage_counties
/
select area_code, area_number, name, seq_num, area
from stage_counties
order by seq_num, name
/
select area_code, area_number, name, num_pts
, sdo_geom.sdo_area(geom, unit=>'unit=sq_km') ireland_area
from my_areas
WHERE area_code = 'SOVC'
and   area_number = 1159320877
/

spool off


select sdo_geom.sdo_area(x.geom, unit=>'unit=sq_km') stage
,      sdo_geom.sdo_area(m.geom, unit=>'unit=sq_km') my_areas
,      sdo_geom.sdo_area(SDO_GEOM.sdo_intersection(m.geom,x.geom,0.001), unit=>'unit=sq_km')
from stage_counties x, my_areas m
WHERE m.area_code = 'SOVC'
and   m.area_number = 1159320877
/

select m.name
,      sdo_geom.sdo_area(x.geom, unit=>'unit=sq_km') stage
,      sdo_geom.sdo_area(m.geom, unit=>'unit=sq_km') my_areas
,      sdo_geom.sdo_area(SDO_GEOM.sdo_intersection(m.geom,x.geom,0.001), unit=>'unit=sq_km') intersection
from my_areas x, my_areas m
WHERE m.parent_area_code = 'SOVC'
and   m.parent_area_number = 1159320877
and   x.area_code = 'SOVC'
and   x.area_number = 1159320877
--fetch first 1 rows only
order by 1
/