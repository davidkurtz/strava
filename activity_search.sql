WITH x AS (
SELECT a.activity_id, m.area_code, m.area_number, m.parent_area_code, m.parent_area_number, m.name, m.name_hierarchy
FROM   my_areas m, activity_areas a
WHERE  m.area_Code = a.area_code
AND    m.area_number = a.area_number
AND    CONTAINS(name,'berkshire',1)>0
) 
SELECT a.activity_id, a.activity_date, a.activity_name, a.activity_type, a.distance_km
,      x.area_Code, x.area_number, x.name, x.name_hierarchy
FROM   x, activities a
WHERE  x.activity_id = a.activity_id
AND    a.activity_date between TO_DATE('01022019','DDMMYYYY') and TO_DATE('28022019','DDMMYYYY')
AND NOT EXISTS (
  SELECT 'x' FROM x x1
  WHERE  x1.area_code = x.parent_area_code
  AND    x1.area_number = x.parent_area_number
  AND    x1.activity_id = x.activity_id)
ORDER BY a.activity_date
/




set serveroutput on
exec strava_pkg.activity_area_hsearch(4347280348);

set serveroutput on
DECLARE
  l_rowid ROWID;
  l_clob CLOB;
BEGIN
  select rowid
  into   l_rowid
  FROM   my_areas m
  WHERE  area_code = 'WAT'
  And    area_number = '15806';

  strava_pkg.name_hierarchy_txtidx(l_rowid, l_clob);
  dbms_output.put_line(l_clob);
END;
/


