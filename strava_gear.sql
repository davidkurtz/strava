REM strava_gear.sql
clear screen
set echo on timi on serveroutput on
spool strava_gear.lst

--DROP TABLE strava.gear PURGE;

CREATE TABLE strava.gear 
(gear_id            VARCHAR2(20) NOT NULL
,primary            BOOLEAN
,name               VARCHAR2(60) 
,nickname           VARCHAR2(60) 
,resource_state     INTEGER
,retired            BOOLEAN
,distance_m         INTEGER      
,distance_km        NUMBER       
,brand_name         VARCHAR2(60) 
,model_name         VARCHAR2(60)
--frame_type
,description        CLOB
,weight             NUMBER       
,last_updated       TIMESTAMP DEFAULT SYSTIMESTAMP
,CONSTRAINT gear_pk PRIMARY KEY(gear_id)
);

desc gear

CREATE OR REPLACE TRIGGER strava.gear_last_updated
BEFORE INSERT OR UPDATE ON gear
FOR EACH ROW
BEGIN
  :new.last_updated := SYSTIMESTAMP AT TIME ZONE 'UTC';
END;
/
show errors

CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW strava.gear_dv AS
SELECT JSON {'_id'    : g.gear_id
,'primary'            : g.primary
,'name'               : g.name
,'nickname'           : g.nickname
,'resource_state'     : g.resource_state
,'retired'            : g.retired
,'distance'           : g.distance_m
,'converted_distance' : g.distance_km
,'brand_name'         : g.brand_name
,'model_name'         : g.model_name
--frame_type
,'description'        : g.description
,'weight'             : g.weight
}
FROM strava.gear g
WITH INSERT UPDATE 
/

desc gear_dv

--truncate table gear;
clear screen 
set echo on serveroutput on 
exec strava_http.get_gear('b4922223');
exec strava_http.get_gear('b993101');
exec strava_http.get_gear('b9149202');
exec strava_http.get_gear('b861402');
exec strava_http.get_gear('b2237986');
exec strava_http.get_gear('b4726660');
exec strava_http.get_gear('b4741153');
exec strava_http.get_gear('b4872537');
exec strava_http.get_gear('b4872607');
exec strava_http.get_gear('b4907360');

--now repeat a few commands
exec strava_http.get_gear('b993101');
exec strava_http.get_gear('b993101');
exec strava_http.get_gear('b9149202');

set echo on
--footware
exec strava_http.get_gear('g13860069');
exec strava_http.get_gear('g15649396');

select * from gear order by gear_id;
select * from gear_dv;

REM check all loaded
select distinct gear_id from activities where gear_id is not null
minus
select gear_id from gear;

spool off