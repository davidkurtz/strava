set serveroutput on timi on
BEGIN
 FOR i IN (
  SELECT activity_id, activity_type, activity_date, activity_name, num_pts, xmlns, filename
  from activities
  where filename is not null
  and geom is null
  order by activity_type, activity_date desc
  fetch first 100 rows only
 ) LOOP
  dbms_output.put_line(i.activity_id||':'||i.activity_date||':'||i.activity_name);
  strava_pkg.load_activity(i.activity_id);
 END LOOP;
 commit;
END;
/

