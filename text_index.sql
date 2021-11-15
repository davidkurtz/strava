REM text_index.sql
----------------------------------------------------------------------------------------------------
--test area_hierarchy procedure
----------------------------------------------------------------------------------------------------
set serveroutput on
DECLARE
  l_rowid ROWID;
  l_clob CLOB;
BEGIN
  select rowid
  into   l_rowid
  FROM   my_areas m
  WHERE  area_code = 'CPC'
  And    area_number = '40307';

  strava_pkg.name_hierarchy_txtidx(l_rowid, l_clob);
  dbms_output.put_line(l_clob);
END;
/
/*should get: 
Streatley, West Berkshire, England, United Kingdom
----------------------------------------------------------------------------------------------------
--test area hierarchy function
----------------------------------------------------------------------------------------------------*/
set serveroutput on
DECLARE
  l_clob CLOB;
  l_my_areas my_areas%ROWTYPE;
BEGIN
  select m.*
  into   l_my_areas
  FROM   my_areas m
  WHERE  area_code = 'CPC'
  And    area_number = '40307';

  dbms_output.put_line(strava_pkg.name_hierarchy_fn(l_my_areas.area_code,l_my_areas.area_number));
  dbms_output.put_line(strava_pkg.name_hierarchy_fn(l_my_areas.parent_area_code,l_my_areas.parent_area_number));
END;
/
/*should get:
Streatley, West Berkshire, England, United Kingdom
West Berkshire, England, United Kingdom
----------------------------------------------------------------------------------------------------*/
----------------------------------------------------------------------------------------------------
ALTER TABLE my_areas DROP COLUMN name_heirarchy;
ALTER TABLE my_areas add name_hierarchy VARCHAR(4000);

/*
UPDATE my_areas
SET name_hierarchy = strava_pkg.name_hierarchy_fn(parent_area_code,parent_area_number)
WHERE parent_area_code IS NOT NULL
AND   parent_area_number IS NOT NULL;

ORA-04091: table STRAVA.MY_AREAS is mutating, trigger/function may not see it
ORA-06512: at "STRAVA.STRAVA_PKG", line 339
ORA-06512: at "STRAVA.STRAVA_PKG", line 339
ORA-06512: at line 1
*/

drop table my_areas_temp purge;
create global temporary table my_areas_temp on commit preserve rows as 
SELECT area_code, area_number, strava_pkg.name_hierarchy_fn(parent_area_code,parent_area_number) name_hierarchy
FROM my_areas where parent_area_code IS NOT NULL AND parent_area_number IS NOT NULL;
MERGE INTO my_areas u 
USING (SELECT * FROM my_areas_temp) s
ON (u.area_code = s.area_code AND u.area_number = s.area_number)
WHEN MATCHED THEN UPDATE
SET u.name_hierarchy = s.name_hierarchy;
DROP TABLE my_areas_Temp PURGE;
----------------------------------------------------------------------------------------------------
Exec ctx_ddl.drop_preference('my_areas_lexer');  
Exec ctx_ddl.drop_preference('my_areas_datastore'); 
drop index my_areas_name_txtidx;

begin
 ctx_ddl.create_preference('my_areas_lexer', 'BASIC_LEXER');  
 ctx_ddl.set_attribute('my_areas_lexer', 'mixed_case', 'NO'); 
 ctx_ddl.create_preference('my_areas_datastore', 'MULTI_COLUMN_DATASTORE'); 
 ctx_ddl.set_attribute('my_areas_datastore', 'columns', 'name, name_hierarchy'); 
end;
/

drop index my_areas_name_txtidx;
create index my_areas_name_txtidx on my_areas (name) indextype is ctxsys.context 
parameters ('datastore my_areas_datastore lexer my_areas_lexer sync(on commit)');

exec ctx_ddl.sync_index('my_areas_name_txtidx');



----------------------------------------------------------------------------------------------------
--build text index with user_datastore
Exec ctx_ddl.drop_preference('my_areas_lexer');  
Exec ctx_ddl.drop_preference('my_areas_datastore'); 
drop index my_areas_name_txtidx;

begin
  ctx_ddl.create_preference('my_areas_lexer', 'BASIC_LEXER');  
  ctx_ddl.set_attribute('my_areas_lexer', 'mixed_case', 'NO'); 
  ctx_ddl.create_preference('my_areas_datastore', 'user_datastore'); 
  ctx_ddl.set_attribute('my_areas_datastore', 'procedure', 'strava_pkg.name_hierarchy_txtidx'); 
  ctx_ddl.set_attribute('my_areas_datastore', 'output_type', 'CLOB');
end;
/

create index my_areas_name_txtidx on my_areas (name) indextype is ctxsys.context 
parameters ('datastore my_areas_datastore lexer my_areas_lexer');
-- sync(on commit) -- wont sync on commit because could be affected by hierarchy changes

--manual sync
exec ctx_ddl.sync_index('my_areas_name_txtidx');


----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
set lines 180
column area_Code heading 'Area|Code'
column area_number heading 'Area|Number' 
column suffix format a10
column name format a25
column name_hierarchy format a75
column matchable heading 'Match|-able' format 9
select score(1), area_Code, area_number, name
--, suffix
--, matchable
--, parent_area_code, parent_area_number, area_level
--, sdo_geom.sdo_area(geom) area
, name_hierarchy
from my_areas m
--where contains(name,'streatley',1)>0
where contains(name,'streatley and berkshire',1)>0
--where contains(name,'Twyford',1)>0
--where contains(name,'berkshire',1)>0
--where contains(name,'lairg',1)>0
--where contains(name,'meriden',1)>0
--where contains(name,'oxford% and district',1)>0
--and matchable = 1
order by name
/

----------------------------------------------------------------------------------------------------
--simple search
----------------------------------------------------------------------------------------------------
set lines 180
column name_hierarchy format a80
select score(1), area_Code, area_number, name, suffix, name_hierarchy
from my_areas m
--where contains(name,'streatley',1)>0
--where contains(name,'streatley and berkshire',1)>0
where contains(name,'berkshire',1)>0
/



----------------------------------------------------------------------------------------------------
--search for highest matching area in hierarchy
----------------------------------------------------------------------------------------------------
column area_Code heading 'Area|Code'
column area_number heading 'Area|Number' 
column name format a25
column name_hierarchy format a60
column parent_area_code heading 'Parent|Area Code'
column parent_area_number heading 'Parent|Area Number'
WITH x AS (
SELECT area_code, area_number, parent_area_code, parent_area_number, name, name_hierarchy
from my_areas m
where contains(name,'berkshire',1)>0
--where contains(name,'Devon',1)>0
--where contains(name,'England',1)>0
) SELECT * FROM x WHERE NOT EXISTS (
  SELECT 'x' FROM x x1
  WHERE  x1.area_code = x.parent_area_code
  AND    x1.area_number = x.parent_area_number
)
/


----------------------------------------------------------------------------------------------------
--search for activity in matching area but return highest match area in hierarchy for each activity
----------------------------------------------------------------------------------------------------
alter session set nls_date_Format = 'DD-MON-YY';
set lines 180 pages 99
column activity_name format a51
column activity_id heading 'Activity|ID' format 9999999999
column activity_date heading 'Activity|Date' format a9
column activity_type heading 'Activity|Type' format a10
column distance_km heading 'Distance|(km)'  format 999.99
column area_code heading 'Area|Code' format a4
column area_number heading 'Area|Number' format 999999
column name format a20
column name_hierarchy format a30
WITH x AS (
SELECT a.activity_id, m.area_code, m.area_number, m.parent_area_code, m.parent_area_number, m.name, m.name_hierarchy
from   my_areas m, activity_areas a
where  m.area_Code = a.area_code
and    m.area_number = a.area_number
and    contains(name,'berkshire',1)>0
) 
SELECT a.activity_id, a.activity_date, a.activity_name, a.activity_type, a.distance_km
,      x.area_Code, x.area_number, x.name, x.name_hierarchy
FROM   x, activities a
WHERE  x.activity_id = a.activity_id
AND    a.activity_date > TO_DATE('01012020','DDMMYYYY')
AND NOT EXISTS (
  SELECT 'x' FROM x x1
  WHERE  x1.area_code = x.parent_area_code
  AND    x1.area_number = x.parent_area_number
  AND    x1.activity_id = x.activity_id)
ORDER BY a.activity_date
/

column activity_name format a35
WITH x AS (
SELECT aa.activity_id, m.area_code, m.area_number, m.parent_area_code, m.parent_area_number, m.name, m.name_hierarchy
FROM   my_areas m, activity_areas aa
WHERE  m.area_Code = aa.area_code
AND    m.area_number = aa.area_number
AND    CONTAINS(name,'Nuremberg',1)>0
) 
SELECT a.activity_id, a.activity_date, a.activity_name, a.activity_type, a.distance_km, x.area_Code, x.area_number, x.name, x.name_hierarchy
FROM   x, activities a
WHERE  x.activity_id = a.activity_id
AND NOT EXISTS (SELECT 'x' FROM x x1
                WHERE  x1.area_code = x.parent_area_code
                AND    x1.area_number = x.parent_area_number
                AND    x1.activity_id = x.activity_id)
ORDER BY a.activity_date;


select distinct activity_type from activities;