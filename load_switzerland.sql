REM load_switzerland.sql

UPDATE my_areas
SET name = 'Zürich'
where (area_code,area_number) IN(('CANT', 765010),('BZRK',1120))
/

----------------------------------------------------------------------------------------------------
--mark activities from recalculation
----------------------------------------------------------------------------------------------------
MERGE INTO activities u
USING (
select a.activity_id, a.name, a.start_date_utc, a.processing_status, a.last_updated activity_last_updated
, MAX(ma.last_updated) area_last_updated
from activities a
  INNER JOIN activity_areas aa ON a.activity_id = aa.activity_id
  INNER JOIN my_areas ma ON ma.area_code =aa.area_code and ma.area_number = aa.area_number
where ma.last_updated > sysdate -7
and a.last_updated < ma.last_updated
and a.processing_status > 3
and a.processing_status < 9
and ma.name_hierarchy like 'Switzerland%'
group by a.activity_id, a.name, a.start_date_utc, a.processing_status, a.last_updated 
) s
ON (s.activity_id = u.activity_id)
WHEN MATCHED THEN UPDATE
SET u.processing_status = 3
/
----------------------------------------------------------------------------------------------------
--force mark Switzerland activities from recalculation
----------------------------------------------------------------------------------------------------
update activities
set processing_status = 3
where processing_status > 3 and processing_status < 9
and activity_id IN(
  select distinct aa.activity_id
  from activity_areas aa 
     INNER JOIN my_areas ma ON ma.area_code =aa.area_code and ma.area_number = aa.area_number
  where ma.name_hierarchy like 'Switzerland%')
/

----------------------------------------------------------------------------------------------------
-- Switzerland activities
----------------------------------------------------------------------------------------------------
select activity_id, start_date_utc, name, type, area_list, processing_from activities
where activity_id IN(
  select distinct aa.activity_id
  from activity_areas aa 
     INNER JOIN my_areas ma ON ma.area_code =aa.area_code and ma.area_number = aa.area_number
  where ma.name_hierarchy like 'Switzerland%')
order by start_date_utc desc
/

----------------------------------------------------------------------------------------------------
-- Switzerland area hierarchy
----------------------------------------------------------------------------------------------------
SELECT area_code, area_number, name, level
, sys_connect_by_path(area_code||':'||area_number||':'||name||' ('||NVL(num_children,0)||')','/') path
FROM   my_areas m
WHERE matchable = 1
START WITH area_code = 'SOVC' AND area_number = 1159320491 and name = 'Switzerland'
CONNECT BY NOCYCLE prior m.area_code   = m.parent_area_code
               AND prior m.area_number = m.parent_area_number
/

SELECT area_code, area_number, name, level
, sys_connect_by_path(area_code||':'||area_number||':'||name||' ('||NVL(num_children,0)||')','/') path
FROM   my_areas m
WHERE matchable = 1
START WITH name = 'Switzerland' AND area_code = 'SOVC' AND area_number = 1159320491 
CONNECT BY NOCYCLE prior m.area_code   = m.parent_area_code
               AND prior m.area_number = m.parent_area_number
/