REM update_my_areas_name_hierarchhy.sql
clear screen
set echo on 
spool update_my_areas_name_hierarchhy.lst

alter TRIGGER strava.my_areas_update_name disable;

--reset heirarchies
update my_areas
set name_hierarchy = name
where parent_area_code is null
and parent_area_number is null
and name_hierarchy IS NULL
and 1=2
/

set echo on
drop table my_area_hierarchy
/
create global temporary table my_area_hierarchy
(area_Code varchar2(4) not null
,area_number integer not null
,name_hierarchy VARCHAR2(4000)
,constraint my_area_hierarchy_pk primary key  (area_code, area_number)
) on commit delete rows;

select count(*), count(name_hierarchy)
from my_areas;

truncate table my_area_hierarchy;
insert into my_area_hierarchy
select area_code, area_number
, strava_sdo.name_hierarchy_fn(area_code, area_number, 'A') name_hierarchy_fn
from my_areas
where name_hierarchy IS null
or parent_area_code = 'UCTL'
or area_code = 'UCTL'
--fetch first 10000 rows only
;
select * from my_area_hierarchy;

merge into my_areas u
using (
select * from my_area_hierarchy
) s on (s.area_code = u.area_code and s.area_number = u.area_number)
when matched then update
set u.name_hierarchy = s.name_hierarchy;

commit;

alter TRIGGER strava.my_areas_update_name enable;

spool off


select * from my_areas
where name like '%Kilruddery%';
