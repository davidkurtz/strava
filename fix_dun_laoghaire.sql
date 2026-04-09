REM fix_dun_laoghaire.sql
clear screen
set echo on serveroutput on timi on 
spool fix_dun_laoghaire.lst

update my_areas
set name = 'Dún Laoghaire'
--set name = 'Dun Laoghaire'
--set name = CONVERT('Dún Laoghaire', 'AL32UTF8','WE8MSWIN1252')
where area_code = 'TOWN'
and area_number = 260358;
commit;

update my_areas
set matchable = 1
where area_code = 'TOWN'
and area_number IN(260358 /*Dun Laoghaire*/);

update my_areas
set matchable = 0
where matchable != 0
and parent_area_code = 'SETL' and parent_area_number = 35001 --Dublin and Suburbs
and ((area_code = 'TOWN' and area_number IN(260324)) --Dalkey Island 
or area_code = 'UCTL')
;
commit;

select area_code, area_number, name, matchable
from my_areas
where parent_area_code = 'SETL'
and parent_area_number = 35001
and matchable = 1
order by name
/


select 'Co. '||name new_name
from my_areas
where area_code = 'CTY'
and parent_area_code = 'PROV'
and uqid like 'IRL%'
and not name like 'Co. %'
and 1=2
/

commit;

clear screen
set serveroutput on
EXECUTE dbms_Scheduler.run_job('STRAVA.ACTIVITY_AREA_LIST_UPD_ALL_JOB',FALSE);

spool OFF

