REM strava_webhooks.sql
----------------------------------------------------------------------------------------------------
-- webhook inbound events queue
----------------------------------------------------------------------------------------------------
set echo on
--DROP TABLE strava.webhook_events  PURGE;
CREATE TABLE strava.webhook_events
(ID                NUMBER                   GENERATED ALWAYS AS IDENTITY
,PAYLOAD           CLOB
,processing_status NUMBER DEFAULT 0 NOT NULL
,RECEIVED_AT       TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP AT TIME ZONE 'UTC'
,last_updated      TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP AT TIME ZONE 'UTC'
,CONSTRAINT webhook_events_pk PRIMARY KEY (id)
);

ALTER TABLE strava.webhook_events ADD processing_status NUMBER DEFAULT 0;
UPDATE strava.webhook_events SET processing_status = 0;
ALTER TABLE strava.webhook_events MODIFY processing_status NOT NULL;

ALTER TABLE strava.webhook_events ADD status_msg CLOB;

ALTER TABLE strava.webhook_events DROP COLUMN aspect_type;
ALTER TABLE strava.webhook_events DROP COLUMN event_timestamp;
ALTER TABLE strava.webhook_events DROP COLUMN event_time;
ALTER TABLE strava.webhook_events DROP COLUMN object_id;
ALTER TABLE strava.webhook_events DROP COLUMN object_type;
ALTER TABLE strava.webhook_events DROP COLUMN owner_id;
ALTER TABLE strava.webhook_events DROP COLUMN subscription_id;
ALTER TABLE strava.webhook_events DROP COLUMN updates;

ALTER TABLE strava.webhook_events ADD aspect_type 
   GENERATED ALWAYS AS (JSON_VALUE(payload, '$."aspect_type"')) VIRTUAL;
ALTER TABLE strava.webhook_events ADD event_time NUMBER 
   GENERATED ALWAYS AS (JSON_VALUE(payload, '$."event_time"' )) VIRTUAL;
ALTER TABLE strava.webhook_events ADD event_timestamp TIMESTAMP WITH TIME ZONE 
   GENERATED ALWAYS AS (strava.epoch_to_tstz(JSON_VALUE(payload, '$."event_time"'))) VIRTUAL;
ALTER TABLE strava.webhook_events ADD object_id NUMBER 
   GENERATED ALWAYS AS (JSON_VALUE(payload, '$."object_id"'  )) VIRTUAL;
ALTER TABLE strava.webhook_events ADD object_type 
   GENERATED ALWAYS AS (JSON_VALUE(payload, '$."object_type"')) VIRTUAL;
ALTER TABLE strava.webhook_events ADD owner_id NUMBER   
   GENERATED ALWAYS AS (JSON_VALUE(payload, '$."owner_id"'   )) VIRTUAL;
ALTER TABLE strava.webhook_events ADD subscription_id NUMBER   
   GENERATED ALWAYS AS (JSON_VALUE(payload, '$."subscription_id"')) VIRTUAL;
ALTER TABLE strava.webhook_events ADD updates     
   GENERATED ALWAYS AS (JSON_QUERY(payload, '$."updates"'    )) VIRTUAL;

ALTER TABLE strava.webhook_events MOVE TABLESPACE data UPDATE INDEXES;

select * from strava.webhook_events order by received_at desc fetch first 5 rows ONLY
/

----------------------------------------------------------------------------------------------------
-- trigger to maintain last update date time
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER strava.webhook_events_last_updated
BEFORE INSERT OR UPDATE ON strava.webhook_events
FOR EACH ROW
BEGIN
  :new.last_updated := SYSTIMESTAMP AT TIME ZONE 'UTC';
END;
/
show errors

----------------------------------------------------------------------------------------------------
-- trigger scheduler to process queue asynchronously
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER strava.webhook_events_process_queue
AFTER INSERT OR UPDATE ON strava.webhook_events
FOR EACH ROW
DECLARE
  PRAGMA autonomous_transaction;
  k_job_name CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.PROCESS_WEBHOOK_QUEUE_JOB';
BEGIN
  IF :new.processing_status = 0 THEN
    dbms_scheduler.set_attribute(name => k_job_name, 
	                             attribute => 'START_DATE', value => SYSTIMESTAMP + INTERVAL '20' SECOND);
    --dbms_scheduler.enable(name => k_job_name);
	--dbms_scheduler.run_job(job_name => 'STRAVA.PROCESS_WEBHOOK_QUEUE_JOB', use_current_session => FALSE);
  END IF;
END;
/
show errors
ALTER TRIGGER strava.webhook_events_process_queue ENABLE;
----------------------------------------------------------------------------------------------------
-- a JSON duality view that I didnt use 
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW strava.webhook_events_dv
AS
SELECT JSON {'_id'    : e.id
,'object_type'        : e.object_type
,'object_id'          : e.object_id
,'aspect_type'        : e.aspect_type
--not using subscription id
,'owner_id'           : e.owner_id
,'event_time'         : e.event_time
}
FROM strava.webhook_events e
WITH INSERT UPDATE 
/
show errors

@@strava_webhook_pkg.sql
----------------------------------------------------------------------------------------------------
--Test Get handler package without STRAVA
----------------------------------------------------------------------------------------------------
DECLARE
  l_hub_challenge    VARCHAR2(100 CHAR);
  l_hub_verify_token VARCHAR2(100 CHAR);
  l_query_string     VARCHAR2(1000 CHAR);
  l_response         CLOB;
  l_message          CLOB;
  l_status_code      NUMBER;
BEGIN 
  l_query_string     := 'hub.verify_token=PlaceCloud42&hub.challenge=abc123&hub.mode=subscribe';
  l_hub_challenge    := regexp_substr(l_query_string, 'hub.challenge=sss([^&]+)', 1, 1, null, 1);
  l_hub_verify_token := regexp_substr(l_query_string, 'hub.verify_token=([^&]+)', 1, 1, null, 1);
  dbms_output.put_line('Hub Challenge='||l_hub_challenge);
  dbms_output.put_line('Hub Verify Token='||l_hub_verify_token);
  strava.webhook_pkg.handle_get(l_hub_challenge, 'PlaceCloud42', l_response, l_status_code, l_message); 
  dbms_output.put_line('Response='||l_response);
  dbms_output.put_line('Status Code='||l_status_code||', '||l_message);
END;
/
----------------------------------------------------------------------------------------------------
--Test Post handler package without STRAVA
----------------------------------------------------------------------------------------------------
clear screen
set echo on serveroutput on 
DECLARE
  l_status_code NUMBER;
BEGIN
   STRAVA.WEBHOOK_PKG.handle_post(
    '{"aspect_type":"update"
	,"event_time":1772838788
	,"object_id":17629666911
	,"object_type":"activity"
	,"owner_id":1679301
	,"subscription_id":333227
	,"updates":{"title":"Sallynoggin"}
	}'	
  ,l_status_code
  );
  dbms_output.put_line('status code:'||l_status_code);
END;
/
select * from strava.webhook_events order by received_at desc;
select * from strava.webhook_events_dv;

----------------------------------------------------------------------------------------------------
-- create the rest service
----------------------------------------------------------------------------------------------------
BEGIN
  ORDS.DROP_REST_FOR_SCHEMA('strava');
  commit;
  
  ORDS.ENABLE_SCHEMA(
    p_enabled             => TRUE,
    p_schema              => 'STRAVA',
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'strava',
    p_auto_rest_auth      => FALSE
  );
  commit;
  
  ORDS.ENABLE_OBJECT(
    p_enabled => TRUE,
    p_schema => 'STRAVA',
    p_object => 'WEBHOOK_EVENTS',
    p_object_type => 'TABLE',
    --p_object_alias => 'placecloud',
    p_auto_rest_auth => FALSE);
  commit;

  ORDS.DEFINE_MODULE(
    p_module_name    => 'placecloud',
    p_base_path      => 'placecloud/'
  );
  commit;

  ORDS.DEFINE_TEMPLATE(
    p_module_name => 'placecloud',
    p_pattern     => 'event'
  );
  commit;

  -- POST handler
  ORDS.DEFINE_HANDLER(
    p_module_name => 'placecloud',
    p_pattern     => 'event',
    p_method      => 'POST',
    p_source_type => ORDS.SOURCE_TYPE_PLSQL,
    p_source      => q'[
	BEGIN strava.webhook_pkg.handle_post(:body_text,:status_code); END;
	]'
  );
  commit;

  /*parameters in traditional query string with explicit variables*/
  -- GET (verification)
  ORDS.DEFINE_HANDLER(
    p_module_name => 'placecloud',
    p_pattern     => 'event',
    p_method      => 'GET',
    p_source_type => ORDS.SOURCE_TYPE_PLSQL,  
    p_source      => q'[
	  DECLARE
	    l_status_code NUMBER;
		l_response    VARCHAR2(200 CHAR);
		l_message     CLOB;
	  BEGIN 
	    strava.webhook_pkg.handle_get(:hub_challenge, :hub_verify_token, l_response, l_status_code, l_message); 
		owa_util.status_line(l_status_code, l_message, FALSE);
        owa_util.mime_header('application/json', FALSE);
		:status_code := l_status_code;
        owa_util.http_header_close;
		htp.p(l_response);
		:response := l_response;
	  END;
	  ]',
    p_mimes_allowed => 'application/json',
 	p_items_per_page => 0
  );
  COMMIT;

  /*parameters in traditional query string*/
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'placecloud',
    p_pattern            => 'event',
    p_method             => 'GET',
    p_name               => 'hub.challenge',
    p_bind_variable_name => 'hub_challenge',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
	p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'placecloud',
    p_pattern            => 'event',
    p_method             => 'GET',
    p_name               => 'hub.verify_token',
    p_bind_variable_name => 'hub_verify_token',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
	p_access_method      => 'IN'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name        => 'placecloud',
    p_pattern            => 'event',
    p_method             => 'GET',
    p_name               => 'hub.mode',
    p_bind_variable_name => 'hub_mode',
    p_source_type        => 'URI',
    p_param_type         => 'STRING',
	p_access_method      => 'IN'
  );
  COMMIT;

END;
/
show errors
--truncate table strava.webhook_events ;
select payload, received_at from strava.webhook_events order by received_at desc;
--select * from dba_constraints where constraint_name = 'REST_PARAMS_SOURCE_TYPE_CK';
----------------------------------------------------------------------------------------------------
--Test ORDS endpoint
--   https://<adb_name>.adb.<region>.oraclecloudapps.com/ords/<schema>/<module>/<template>/
--   https://GE874A6456C1E09-GOFASTER1.adb.uk-london-1.oraclecloudapps.com/ords/strava/placecloud/event/
--   /ords/<schema-alias>/<module-base-path>/<template>/
----------------------------------------------------------------------------------------------------
select * from user_ords_schemas;
select * from user_ords_services; 
select * from user_ords_modules; 
select * from user_ords_templates;
select * from user_ords_handlers; 
select * from user_ords_parameters;

select * from DBA_ORDS_CLIENTS;
select * from DBA_ORDS_CLIENT_PRIVILEGES;
select * from DBA_ORDS_CLIENT_ROLES;
select * from USER_ORDS_ENABLED_OBJECTS;
select * from USER_ORDS_PRIVILEGE_MAPPINGS;
select * from USER_ORDS_PRIVILEGE_MODULES;
select * from dba_views where view_name like 'USER_ORDS%'
/
----------------------------------------------------------------------------------------------------
-- query to report on rest service setup
----------------------------------------------------------------------------------------------------
clear screen columns
column pattern format a8
column uri_prefix format a12
column uri_template format a8
column name format a20
column bind_variable_name format a20
select s.pattern, m.uri_prefix, t.uri_template, h.method, p.name, p.bind_variable_name
from user_ords_schemas s
  inner join user_ords_modules m on m.schema_id = s.id
  inner join user_ords_templates t on t.module_id = m.id
  inner join user_ords_handlers h on h.template_id = t.id
  left outer join user_ords_parameters p on p.handler_id = h.id
/

/*
----------------------------------------------------------------------------------------------------
--URL        : https://GE874A6456C1E09-GOFASTER1.adb.uk-london-1.oraclecloudapps.com/ords/strava/placecloud/event
--Method     : POST
--Header     : Content-Type: application/json
--Raw Payload: C:\Users\david\OneDrive\Documents\SQL\strava\resttest.json
----------------------------------------------------------------------------------------------------


----------------------------------------------------------------------------------------------------
--Test Post Handler:
----------------------------------------------------------------------------------------------------
curl -i -S -X POST --data-ascii @C:\Users\david\OneDrive\Documents\SQL\strava\resttest.json -H "Content-Type: application/json" "https://GE874A6456C1E09-GOFASTER1.adb.uk-london-1.oraclecloudapps.com/ords/strava/placecloud/event"
----------------------------------------------------------------------------------------------------


----------------------------------------------------------------------------------------------------
--Test GET Handler:
----------------------------------------------------------------------------------------------------
curl -i -S -X GET -H "Content-Type: application/json" "https://GE874A6456C1E09-GOFASTER1.adb.uk-london-1.oraclecloudapps.com/ords/strava/placecloud/event?hub.verify_token=PlaceCloud42&hub.challenge=abc123&hub.mode=subscribe"
----------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------
curl -G https://www.strava.com/api/v3/push_subscriptions -d client_id=145581 -d client_secret=5413e6216e97ee55ead4e673fe23e337fba64642
----------------------------------------------------------------------------------------------------
[{"id":333227,"resource_state":2,"application_id":145581,"callback_url":"https://GE874A6456C1E09-GOFASTER1.adb.uk-london-1.oraclecloudapps.com/ords/strava/placecloud/event","created_at":"2026-03-03T21:58:49+00:00","updated_at":"2026-03-03T21:58:49+00:00"}]
----------------------------------------------------------------------------------------------------
*/	  

  
----------------------------------------------------------------------------------------------------
-- create the strava subscription
----------------------------------------------------------------------------------------------------
--clear screen
--set echo on serveroutput on size unlimited
--exec strava.strava_http.create_webhook('https://GE874A6456C1E09-GOFASTER1.adb.uk-london-1.oraclecloudapps.com/ords/strava/placecloud/event');
select * from strava.webhook_events order by received_at desc fetch first 5 rows ONLY;

----------------------------------------------------------------------------------------------------
--get strava subscription details
----------------------------------------------------------------------------------------------------
BEGIN
  renew_strava_tokens;
  dbms_output.put_line(strava_http.strava_http_request('https://www.strava.com/api/v3/push_subscriptions','GET'));
END;
/

----------------------------------------------------------------------------------------------------
-- this is the queue
----------------------------------------------------------------------------------------------------
--delete from strava.webhook_events where id IN(294,295);
select * from strava.webhook_events 
--where processing_status <= 0
order by received_at desc 
--fetch first 5 rows ONLY
/
----------------------------------------------------------------------------------------------------
-- show all versions of an activity with a flashback query
----------------------------------------------------------------------------------------------------
show parameters undo
select activity_id, versions_endscn
, last_updated, area_list, description , processing_status
from activities 
VERSIONS BETWEEN TIMESTAMP systimestamp - INTERVAL '56' HOUR
                        AND systimestamp
where activity_id = 17892214718
order by 2, last_updated
;

--update activities set processing_status = 4 where activity_id = 17639318537;
----------------------------------------------------------------------------------------------------
-- queue processing jobs
----------------------------------------------------------------------------------------------------
select * from dba_scheduler_jobs where owner = 'STRAVA' AND job_name = 'PROCESS_WEBHOOK_QUEUE_JOB';
select * from dba_scheduler_job_run_details where owner = 'STRAVA' and job_name = 'PROCESS_WEBHOOK_QUEUE_JOB'
ORDER BY 1 desc,2 
FETCH FIRST 50 ROWS ONLY
/


----------------------------------------------------------------------------------------------------
--reprocess messages that have errored
----------------------------------------------------------------------------------------------------
update webhook_events set processing_status = 0 where processing_status < 0;
commit;

----------------------------------------------------------------------------------------------------
--manually process the queue
----------------------------------------------------------------------------------------------------
set serveroutput on 
exec dbms_scheduler.run_job(job_name => 'STRAVA.PROCESS_WEBHOOK_QUEUE_JOB', use_current_session => FALSE);

DECLARE
  k_job_name CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.PROCESS_WEBHOOK_QUEUE_JOB';
BEGIN
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'START_DATE', value => SYSTIMESTAMP + INTERVAL '1' SECOND);
  dbms_scheduler.enable(name => k_job_name);
  --dbms_scheduler.run_job(job_name => 'STRAVA.PROCESS_WEBHOOK_QUEUE_JOB', use_current_session => FALSE);
END;
/

