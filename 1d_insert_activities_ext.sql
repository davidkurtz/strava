REM 1d_insert_activities_ext
spool 1d_insert_activities_ext
REM delete changed activities so can reload them

DELETE FROM activity_areas 
WHERE  activity_id in(
  SELECT a.activity_id
  from   strava.activities a
  ,      strava.activities_ext e
  where  a.activity_id = e.activity_id
  and   (a.distance_km != e.distance_km
  or     a.elapsed_time != e.elapsed_time))
/

delete from activities 
WHERE  activity_id in(
  SELECT a.activity_id
  from   strava.activities a
  ,      strava.activities_ext e
  where  a.activity_id = e.activity_id
  and   (a.distance_km != e.distance_km
  or     a.elapsed_time != e.elapsed_time))
/

BEGIN
 FOR i IN(
  SELECT e.activity_id, e.activity_name, e.activity_description, e.activity_gear
  from   strava.activities a
  ,      strava.activities_ext e
  where  a.activity_id = e.activity_id
  and    (a.activity_name != e.activity_name
  or      a.activity_description != e.activity_description
  or      a.activity_gear != e.activity_gear)
 ) LOOP
  UPDATE activities a
  SET    a.activity_name = i.activity_name
  ,      a.activity_description = i.activity_description
  ,      a.activity_gear = i.activity_gear
  WHERE  a.activity_id = i.activity_id;
 END LOOP;
END;
/

INSERT INTO strava.activities 
(ACTIVITY_ID,ACTIVITY_DATE,ACTIVITY_NAME,ACTIVITY_TYPE,ACTIVITY_DESCRIPTION,
ELAPSED_TIME,DISTANCE_KM,RELATIVE_EFFORT,COMMUTE_CHAR,ACTIVITY_GEAR,
FILENAME,
ATHLETE_WEIGHT,BIKE_WEIGHT,ELAPSED_TIME2,MOVING_TIME,DISTANCE_M,MAX_SPEED,AVERAGE_SPEED,
ELEVATION_GAIN,ELEVATION_LOSS,ELEVATION_LOW,ELEVATION_HIGH,MAX_GRADE,AVERAGE_GRADE,
MAX_CADENCE,AVERAGE_CADENCE,
AVERAGE_HEART_RATE,AVERAGE_WATTS,CALORIES,RELATIVE_EFFORT2,TOTAL_WORK,
PERCEIVED_EXERTION,WEIGHTED_AVERAGE_POWER,POWER_COUNT,
PREFER_PERCEIVED_EXERTION,PERCEIVED_RELATIVE_EFFORT,
COMMUTE,FROM_UPLOAD,GRADE_ADJUSTED_DISTANCE,BIKE)
select ACTIVITY_ID,ACTIVITY_DATE,ACTIVITY_NAME,ACTIVITY_TYPE,ACTIVITY_DESCRIPTION,
ELAPSED_TIME,DISTANCE_KM,RELATIVE_EFFORT,COMMUTE_CHAR,ACTIVITY_GEAR,
FILENAME,
ATHLETE_WEIGHT,BIKE_WEIGHT,ELAPSED_TIME2,MOVING_TIME,DISTANCE_M,MAX_SPEED,AVERAGE_SPEED,
ELEVATION_GAIN,ELEVATION_LOSS,ELEVATION_LOW,ELEVATION_HIGH,MAX_GRADE,AVERAGE_GRADE,
MAX_CADENCE,AVERAGE_CADENCE,
AVERAGE_HEART_RATE,AVERAGE_WATTS,CALORIES,RELATIVE_EFFORT2,TOTAL_WORK,
PERCEIVED_EXERTION,WEIGHTED_AVERAGE_POWER,POWER_COUNT,
PREFER_PERCEIVED_EXERTION,PERCEIVED_RELATIVE_EFFORT,
COMMUTE,FROM_UPLOAD,GRADE_ADJUSTED_DISTANCE,BIKE
from strava.activities_ext e
where not exists(
  select 'x'
  from   strava.activities a
  where  a.activity_id = e.activity_id)
/

UPDATE activities
SET filename = REPLACE(filename,'.fit.gz','.gpx.gz')
WHERE filename like '%.fit.gz'
/

commit;
spool off
