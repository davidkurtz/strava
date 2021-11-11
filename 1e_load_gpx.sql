REM 1e_load_gpx
set timi on echo on serveroutput on
spool 1e_load_gpx
ROLLBACK;

select  count(*), count(gpx)
from activities
/

UPDATE activities
set filename = filename||'.gz'
where filename like '%.gpx'
/

UPDATE activities
SET gpx = XMLTYPE(strava_pkg.getClobDocument('ACTIVITIES',filename))
WHERE filename like '%.gpx%'
and gpx IS NULL
/

select  count(*), count(gpx)
from activities
/

Set long 1100 lines 200 pages 99 serveroutput on
select *
from activities
where filename like '%.gpx%'
and gpx is not null
and num_pts > 0
order by num_pts 
fetch first 1 rows only 
/

spool off

