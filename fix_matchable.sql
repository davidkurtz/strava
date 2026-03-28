REM fix_matchable.sql
set echo on timi on
clear screen
spool fix_matchable.lst

MERGE INTO my_areas u
USING (
select p.area_level parent_area_level
,      p.area_code parent_area_code
,      p.area_number parent_Area_number
,      p.name parent_name
,      p.matchable parent_matchable
,      c.area_level, c.area_code, c.area_number, c.name, c.matchable
from my_areas c
, my_areas p
WHERE c.parent_area_code = p.area_code
AND c.parent_area_number = p.area_number
AND NOT (c.area_code = p.area_code AND c.area_number != p.area_number)
AND c.matchable = 1
AND p.name = c.name
--AND p.name LIKE c.name||'%'
) S
ON (u.area_code = s.area_Code
and u.area_number = s.area_number)
WHEN MATCHED THEN UPDATE
set u.matchable = 0
;

MERGE INTO my_areas u
USING (
select p.area_level parent_area_level
,      p.area_code parent_area_code
,      p.area_number parent_Area_number
,      p.name parent_name
,      p.matchable parent_matchable
,      c.area_level, c.area_code, c.area_number, c.name, c.matchable
from my_areas c
, my_areas p
WHERE c.parent_area_code = p.area_code
AND c.parent_area_number = p.area_number
AND NOT (c.area_code = p.area_code AND c.area_number != p.area_number)
AND c.matchable = 1
and c.area_level > 4
AND p.name LIKE c.name||', %'
and 1=2
) S
ON (u.area_code = s.area_Code
and u.area_number = s.area_number)
WHEN MATCHED THEN UPDATE
set u.matchable = 0
;

spool off
