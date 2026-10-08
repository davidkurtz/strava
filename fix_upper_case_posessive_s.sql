REM fix_upper_case_posessive_s.sql
update my_areas
set name = regexp_replace(name,'''S','''s')
, last_updated = SYSDATE
where regexp_like(name,'[a-z]+''S[ -]')
/

update my_areas
set name = replace(name,'''S','''s')
, last_updated = SYSDATE
where  name like '%''S'
/


update my_areas
set name_hierarchy = regexp_replace(name_hierarchy,'''S','''s')
, last_updated = SYSDATE
where regexp_like(name_hierarchy,'[a-z]+''S[ -]')
/

update my_areas
set name_hierarchy = replace(name_hierarchy,'''S','''s')
, last_updated = SYSDATE
where  name_hierarchy like '%''S'
/

select name, name_hierarchy
from my_areas
where name like '%''S' 
or regexp_like(name,'[a-z]+''S[ -]')
or name_hierarchy like '%''S' 
or regexp_like(name_hierarchy,'[a-z]+''S[ -]')
/