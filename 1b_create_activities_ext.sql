rem 1b_create_activities_ext.sql
spool 1b_create_activities_ext

REM drop table strava.activities_ext purge;
create table strava.activities_ext
(Activity_ID NUMBER
,Activity_Date DATE
,Activity_Name VARCHAR2(100)
,Activity_Type VARCHAR2(15)
,Activity_Description VARCHAR2(200)
,Elapsed_Time NUMBER
,Distance_km NUMBER
,Relative_Effort NUMBER
,Commute_char VARCHAR2(5)
,Activity_Gear VARCHAR2(100)
,Filename VARCHAR2(100)
,Athlete_Weight NUMBER
,Bike_Weight NUMBER
,Elapsed_Time2 NUMBER
,Moving_Time NUMBER
,Distance_m NUMBER
,Max_Speed NUMBER
,Average_Speed NUMBER
,Elevation_Gain NUMBER
,Elevation_Loss NUMBER
,Elevation_Low NUMBER
,Elevation_High NUMBER
,Max_Grade NUMBER
,Average_Grade NUMBER
,Average_Positive_Grade NUMBER
,Average_Negative_Grade NUMBER
,Max_Cadence NUMBER
,Average_Cadence NUMBER
,Max_Heart_Rate NUMBER
,Average_Heart_Rate NUMBER
,Max_Watts NUMBER
,Average_Watts NUMBER
,Calories NUMBER
,Max_Temperature NUMBER
,Average_Temperature NUMBER
,Relative_Effort2 NUMBER
,Total_Work NUMBER
,Number_of_Runs NUMBER
,Uphill_Time NUMBER
,Downhill_Time NUMBER
,Other_Time NUMBER
,Perceived_Exertion NUMBER
,type NUMBER
,start_time DATE
,Weighted_Average_Power NUMBER
,Power_Count NUMBER
,Prefer_Perceived_Exertion NUMBER
,Perceived_Relative_Effort NUMBER
,Commute NUMBER
,Total_Weight_Lifted NUMBER
,From_Upload NUMBER
,Grade_Adjusted_Distance NUMBER
,Weather_Observation_Time DATE
,Weather_Condition VARCHAR2(100)
,Weather_Temperature NUMBER
,Apparent_Temperature NUMBER
,Dewpoint NUMBER
,Humidity NUMBER
,Weather_Pressure NUMBER
,Wind_Speed NUMBER
,Wind_Gust NUMBER
,Wind_Bearing NUMBER
,Precipitation_Intensity NUMBER
,Sunrise_Time DATE
,Sunset_Time DATE
,Moon_Phase VARCHAR2(100)
,Bike NUMBER
,Gear NUMBER
,Precipitation_Probability NUMBER
,Precipitation_Type NUMBER
,Cloud_Cover NUMBER
,Weather_Visibility NUMBER
,UV_Index NUMBER
,Weather_Ozone NUMBER
,jump_count NUMBER
,total_grit NUMBER
,avg_flow NUMBER
,flagged VARCHAR2(10))
ORGANIZATION EXTERNAL
(TYPE ORACLE_LOADER
 DEFAULT DIRECTORY strava
 ACCESS PARAMETERS 
 (RECORDS DELIMITED BY newline 
  SKIP 1
  DISABLE_DIRECTORY_LINK_CHECK 
  PREPROCESSOR strava:'nlfix.sh' 
  FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' RTRIM
  MISSING FIELD VALUES ARE NULL
  REJECT ROWS WITH ALL NULL FIELDS
  NULLIF = BLANKS
(Activity_ID,Activity_Date date "DD Mon yyyy,HH24:mi:ss"
,Activity_Name,Activity_Type,Activity_Description
,Elapsed_Time,Distance_km
,Relative_Effort
,Commute_char
,Activity_Gear
,Filename
,Athlete_Weight,Bike_Weight
,Elapsed_Time2,Moving_Time,Distance_m,Max_Speed,Average_Speed
,Elevation_Gain,Elevation_Loss,Elevation_Low,Elevation_High,Max_Grade
,Average_Grade,Average_Positive_Grade,Average_Negative_Grade
,Max_Cadence,Average_Cadence
,Max_Heart_Rate,Average_Heart_Rate,Max_Watts,Average_Watts,Calories
,Max_Temperature,Average_Temperature
,Relative_Effort2
,Total_Work
,Number_of_Runs
,Uphill_Time,Downhill_Time,Other_Time
,Perceived_Exertion
,type
,start_time
,Weighted_Average_Power,Power_Count
,Prefer_Perceived_Exertion,Perceived_Relative_Effort
,Commute
,Total_Weight_Lifted
,From_Upload
,Grade_Adjusted_Distance
,Weather_Observation_Time,Weather_Condition,Weather_Temperature
,Apparent_Temperature,Dewpoint,Humidity,Weather_Pressure
,Wind_Speed,Wind_Gust,Wind_Bearing,Precipitation_Intensity
,Sunrise_Time,Sunset_Time,Moon_Phase
,Bike,Gear
,Precipitation_Probability,Precipitation_Type
,Cloud_Cover,Weather_Visibility,UV_Index,Weather_Ozone
,jump_count,total_grit,avg_flow
,flagged))
LOCATION ('activities.csv')
) REJECT LIMIT 5
/

set pages 99 lines 200 trimspool on
alter session set nls_date_Format = 'hh24:mi:ss dd.mm.yyyy';

select *
from strava.activities_ext
where rownum <= 10
/
spool off
