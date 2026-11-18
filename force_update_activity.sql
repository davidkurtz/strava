set lines 150 serveroutput on LONG 50000
column activity_id format 99999999999
column name format a60
column area_list format a150
clear screen
help accept
accept activity_id NUMBER prompt "Activity ID:" 
--force update an existing activityy
update activities
set processing_status = 3
where processing_status = 6
--and area_list is not null
and activity_id = &&activity_id
/
commit;
set serveroutput on
--exec strava_http.get_activity(&&activity_id,p_get_stream=>FALSE);
--exec strava_http.get_activity(&&activity_id,p_get_stream=>TRUE);
exec strava_http.update_strava_activity(&&activity_id);
exec STRAVA.STRAVA_SDO.ACTIVITY_HSEARCH_UPD(&&activity_id);
select activity_id, name, processing_status, area_list
from activities
where activity_id = &&activity_id
/
