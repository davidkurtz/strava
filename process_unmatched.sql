REM process_unmatched.sql
spool process_unmatched app
SELECT count(*) acts, count(num_pts) pts_acts, sum(num_pts) sum_pts, sum(distance_km) sum_km
, min(num_pts) min_pts, min(distance_km) min_km
, avg(num_pts) avg_pts, avg(distance_km) avg_km
, median(num_pts) med_pts, median(distance_km) med_km
, max(num_pts) max_pts, max(distance_km) max_km
FROM   activities a
WHERE  activity_id NOT IN (SELECT activity_id FROM activity_areas)
and filename is not null
--and num_pts>0
/

select *
FROM   activities a
WHERE  activity_id NOT IN (SELECT activity_id FROM activity_areas)
and filename is not null
--and num_pts>0
/

   
--process unmatched activities
set pages 99 lines 180 timi on serveroutput on
column activity_name format a60
BEGIN 
  FOR i IN (
    SELECT a.activity_id, activity_date, activity_name
    ,      distance_km, num_pts, ROUND(num_pts/NULLIF(distance_km,0),0) ppkm
    FROM   activities a
    WHERE  activity_id NOT IN (SELECT activity_id FROM activity_areas)
    AND    num_pts>0
    ORDER BY num_pts 
    --FETCH FIRST 50 ROWS ONLY
  ) LOOP
    dbms_output.put_line(i.activity_id||', '||i.activity_date||', '||i.activity_name||', '||i.distance_km||'km, '||i.num_pts||' points');
    strava_pkg.activity_area_search(i.activity_id);
    commit;
  END LOOP;
END;
/
spool off