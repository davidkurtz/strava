REM fix_paris.sql
clear screen
set echo on serveroutput on timi on 
spool fix_paris.lst

update my_areas
set name = 'Paris, 12e arrondissement'
where name = 'Paris, 12e arronissement'
/
commit;

select name
from my_areas
where name = 'Paris, 12e arrondissement'
order by name
/

commit;

clear screen
set serveroutput on
EXECUTE dbms_Scheduler.run_job('STRAVA.ACTIVITY_AREA_LIST_UPD_ALL_JOB');

spool OFF

