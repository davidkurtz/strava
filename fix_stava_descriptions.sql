REM fix_stava_descriptions.sql
clear screen
set echo on
spool fix_stava_descriptions.lst
--SELECT value FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';

----------------------------------------------------------------------------------------------------
--Fix Weather Impact Trade Mark Symbol
----------------------------------------------------------------------------------------------------
merge into activities U
using (
select activity_id, processing_status, description
, LEAST(4,processing_status) new_processing_status
, regexp_replace(description,'Weather Impact[^S]{3,}:'
                            ,'Weather Impact'||UNISTR('\2122')||':'
							,1,1) replaced
from activities
where description like '%myWindsock%Weather Impact%'
and REGEXP_like(description,'Weather Impact(?!' || UNISTR('\2122') || '):')
--and activity_id = 17396816078
) S 
on (s.activity_id = u.activity_id)
when matched then update
set u.description = s.replaced
, u.processing_status = s.new_processing_status
/


----------------------------------------------------------------------------------------------------
-- Fix degree centrigrade with a non degree symbol
----------------------------------------------------------------------------------------------------
merge into activities U
using (
with x as (
select activity_id, processing_status, description
, LEAST(4,processing_status) new_processing_status
, regexp_substr(description,'Temp:[ -.[:digit:]]+[^[:space:]]+C') found_string
, CAST(substr(regexp_substr(description,'Temp:[ -.[:digit:]]+[^[:space:]]+C'),-3,1) AS VARCHAR2(1 CHAR)) found_char
, regexp_instr(description,'Temp:[ -.[:digit:]]+ ',1,1,1)-1 pos1
, regexp_instr(description,'Temp:[ -.[:digit:]]+[^[:space:]]+C',1,1,1)-1 pos2
from activities
where description like '%myWindsock%Weather Impact%'
--and regexp_like(description,'Temp:[ -.[:digit:]]+[^[:space:]]+C')
--and ascii(substr(regexp_substr(description,'Temp:[ -.[:digit:]]+[^S^s]C'),-3,1)) != 32
)
select activity_id, new_processing_status, found_char
, description
, RTRIM(substr(description,1,pos1))||' '||UNISTR('\00b0')||substr(description,pos2) replaced
from x
where 1=1
and (found_char != UNISTR('\00b0') and found_char != ' ')
--and activity_id = 17451087576
) S 
on (s.activity_id = u.activity_id)
when matched then update
set u.description = s.replaced
, u.processing_status = s.new_processing_status
;

----------------------------------------------------------------------------------------------------
--find mutliple placecloud insertions
----------------------------------------------------------------------------------------------------
select activity_id, processing_status
, regexp_count(description,'PlaceCloud')
, description
from activities
where description like '%myWindsock%Weather Impact%'
and regexp_count(description,'PlaceCloud')>1
order by last_updated desc;

----------------------------------------------------------------------------------------------------
clear screen

--exec strava_http.get_activity(16969148050,p_get_stream=>TRUE);
select activity_id, processing_status, last_updated
, description
, strava_http.clean_string(description)
from activities
where activity_id = 17602420473
/
clear screen
set echo on serveroutput on 
exec strava_http.update_strava_activity(17602420473);


EXECUTE dbms_Scheduler.run_job('STRAVA.ACTIVITY_AREA_LIST_UPD_ALL_JOB',FALSE) /*this runs a job to create the update jobs*/; 