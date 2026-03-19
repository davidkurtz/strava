REM strava_job.sql
clear screen
set echo on timi on serveroutput on
spool strava_job.lst
rem requires GRANT MANAGE SCHEDULER TO strava;;
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE strava.strava_job AS
PROCEDURE create_activity_area_list_upd_all_job;
PROCEDURE create_activity_hsearch_upd_all;
PROCEDURE create_activity_hsearch_upd_all_job;
PROCEDURE create_batch_load_activities_job;
PROCEDURE create_update_strava_activity_job;
PROCEDURE create_process_webhook_queue_job;
PROCEDURE create_purge_api_log_job;
PROCEDURE create_purge_event_queue_job;
PROCEDURE create_renew_strava_tokens_job;

PROCEDURE create_get_activity_job
(p_activity_id activities.activity_id%TYPE
);

PROCEDURE create_activity_hsearch_upd_job 
(p_activity_id activities.activity_id%TYPE
);

END strava_job;
/
show errors
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY strava.strava_job AS
----------------------------------------------------------------------------------------------------
--package constants
----------------------------------------------------------------------------------------------------
k_module        CONSTANT VARCHAR2(64 CHAR) := $$PLSQL_UNIT;
----------------------------------------------------------------------------------------------------
k3_status_stream_loaded       CONSTANT INTEGER := 3;
----------------------------------------------------------------------------------------------------
e_job_does_not_exists EXCEPTION;
PRAGMA EXCEPTION_INIT(e_job_does_not_exists,-27476);
e_job_already_exists EXCEPTION;
PRAGMA EXCEPTION_INIT(e_job_already_exists,-27477);
e_job_running EXCEPTION;
PRAGMA EXCEPTION_INIT(e_job_running,-27478);
----------------------------------------------------------------------------------------------------
--create a job class based on delivered job classes
----------------------------------------------------------------------------------------------------
PROCEDURE create_job_class
(p_job_class_name          all_scheduler_job_classes.job_class_name%TYPE
,p_based_on_job_class      all_scheduler_job_classes.job_class_name%TYPE
,p_resource_consumer_group all_scheduler_job_classes.resource_consumer_group%TYPE DEFAULT NULL
,p_service                 all_scheduler_job_classes.service%TYPE                 DEFAULT NULL
,p_logging_level           all_scheduler_job_classes.logging_level%TYPE           DEFAULT NULL
,p_log_history             all_scheduler_job_classes.log_history%TYPE             DEFAULT NULL
,p_comments                all_scheduler_job_classes.comments%TYPE                DEFAULT NULL)
IS
  r_job_class all_scheduler_job_classes%ROWTYPE;

  k_action CONSTANT VARCHAR2(64 CHAR) := 'create_job_class';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  
  SELECT * INTO r_job_class
  FROM   all_scheduler_job_classes
  WHERE  owner = 'SYS'
  AND    job_class_name = p_based_on_job_class;
  
  BEGIN
    DBMS_SCHEDULER.CREATE_JOB_CLASS(p_job_class_name); 
  EXCEPTION 
    WHEN e_job_already_exists THEN NULL;
  END;
  
  IF p_resource_consumer_group IS NOT NULL THEN
    r_job_class.resource_consumer_group := p_resource_consumer_group;
  END IF;
  IF p_service IS NOT NULL THEN
    r_job_class.service := p_service;
  END IF;
  IF p_logging_level IS NOT NULL THEN
    r_job_class.logging_level := p_logging_level;
  END IF;
  IF p_log_history IS NOT NULL THEN
    r_job_class.log_history := p_log_history;
  END IF;
  IF p_comments IS NOT NULL THEN
    r_job_class.comments := p_comments;
  END IF;
  
  dbms_Scheduler.set_attribute(p_job_class_name, 'resource_consumer_group', r_job_class.resource_consumer_group);
  dbms_Scheduler.set_attribute(p_job_class_name, 'service'                , r_job_class.service);

  --dbms_output.put_line('not setting logging_level:'||r_job_class.logging_level);
  IF r_job_class.logging_level = 'OFF' THEN
    dbms_Scheduler.set_attribute(p_job_class_name, 'logging_level', DBMS_SCHEDULER.LOGGING_OFF);
  ELSIF r_job_class.logging_level = 'RUNS' THEN
    dbms_Scheduler.set_attribute(p_job_class_name, 'logging_level', DBMS_SCHEDULER.LOGGING_RUNS);
  ELSIF r_job_class.logging_level = 'FAILED RUNS' THEN
    dbms_Scheduler.set_attribute(p_job_class_name, 'logging_level', DBMS_SCHEDULER.LOGGING_FAILED_RUNS);
  ELSIF r_job_class.logging_level = 'FULL' THEN
    dbms_Scheduler.set_attribute(p_job_class_name, 'logging_level', DBMS_SCHEDULER.LOGGING_FULL);
  END IF;
  dbms_Scheduler.set_attribute(p_job_class_name, 'log_history'            , TO_CHAR(r_job_class.log_history));
  dbms_Scheduler.set_attribute(p_job_class_name, 'comments'               , r_job_class.comments);
  
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN no_data_found THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
	RAISE;
END create_job_class;
----------------------------------------------------------------------------------------------------
PROCEDURE create_activity_area_list_upd_all_job 
IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.ACTIVITY_AREA_LIST_UPD_ALL_JOB';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.ACTIVITY_AREA_LIST_UPD_ALL_CLASS';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);

  create_job_class(k_job_class,'LOW', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => k_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.STRAVA_SDO.ACTIVITY_AREA_LIST_UPD_ALL'
    ,enabled => FALSE
    );
  EXCEPTION WHEN e_job_already_exists THEN NULL;
  END;
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'AUTO_DROP', value => FALSE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_CLASS', value => k_job_class);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'START_DATE'      
                              ,value => TRUNC(SYSTIMESTAMP AT TIME ZONE 'UTC') + INTERVAL '1' DAY);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'REPEAT_INTERVAL' ,value => 'FREQ=DAILY;BYHOUR=4;BYMINUTE=42');
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'NUMBER_OF_ARGUMENTS', value => 0);
  dbms_scheduler.enable(name => k_job_name);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END create_activity_area_list_upd_all_job;
----------------------------------------------------------------------------------------------------
PROCEDURE create_batch_load_activities_job 
IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.BATCH_LOAD_ACTIVITIES_JOB';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.BATCH_LOAD_ACTIVITIES_CLASS';

  l_ts TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;
  l_next_start TIMESTAMP WITH TIME ZONE; 

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);
  
  l_next_start := TRUNC(l_ts, 'HH24') + NUMTODSINTERVAL(CEIL(EXTRACT(MINUTE FROM l_ts) / 15) * 15, 'MINUTE');

  create_job_class(k_job_class,'MEDIUM', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => k_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.STRAVA_HTTP.BATCH_LOAD_ACTIVITIES'
    ,enabled => FALSE
    );
  EXCEPTION WHEN e_job_already_exists THEN NULL;
  END;

  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'AUTO_DROP'           ,value => FALSE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_CLASS'           ,value => k_job_class); 
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'REPEAT_INTERVAL'     
                                                 , value => 'FREQ=DAILY;BYHOUR=0,1,2,9,15,18,21;BYMINUTE=0,15,30,45');
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'NUMBER_OF_ARGUMENTS' ,value => 2);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'START_DATE'          ,value => l_next_start);
  dbms_scheduler.set_job_anydata_value(job_name => k_job_name,argument_position => 1 --quota_pct
                                      ,argument_value => SYS.ANYDATA.convertNumber(80));
  dbms_scheduler.set_job_anydata_value(job_name => k_job_name,argument_position => 2 --quota_abs
                                      ,argument_value => SYS.ANYDATA.convertNumber(80));

  DBMS_SCHEDULER.set_resource_constraint 
  (object_name   => k_job_name
  ,resource_name => 'BATCH_UPDATE_LIMIT'
  ,units         => 1);     

  dbms_scheduler.enable(name => k_job_name);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END create_batch_load_activities_job;
----------------------------------------------------------------------------------------------------
PROCEDURE create_update_strava_activity_job 
IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.UPDATE_STRAVA_ACTIVTY_JOB';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.UPDATE_STRAVA_ACTIVTY_CLASS';


  l_ts TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;
  l_next_start TIMESTAMP WITH TIME ZONE; 

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);
  
  l_next_start := TRUNC(l_ts, 'HH24') + NUMTODSINTERVAL(CEIL(EXTRACT(MINUTE FROM l_ts) / 15) * 15, 'MINUTE');

  create_job_class(k_job_class,'MEDIUM', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => k_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.STRAVA_HTTP.BATCH_UPDATE_STRAVA_ACTIVITY'
    ,enabled => FALSE
    );
  EXCEPTION WHEN e_job_already_exists THEN NULL;
  END;

  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_ACTION',value => 'STRAVA.STRAVA_HTTP.BATCH_UPDATE_STRAVA_ACTIVITY');
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'AUTO_DROP'           ,value => FALSE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_CLASS'           ,value => k_job_class); 
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'REPEAT_INTERVAL'     
                                                 , value => 'FREQ=DAILY;BYHOUR=0,1,2,9,15,18,21;BYMINUTE=0,15,30,45');
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'NUMBER_OF_ARGUMENTS' ,value => 2);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'START_DATE'          ,value => l_next_start);
  dbms_scheduler.set_job_anydata_value(job_name => k_job_name,argument_position => 1 --quota_pct
                                      ,argument_value => SYS.ANYDATA.convertNumber(80)); 
  dbms_scheduler.set_job_anydata_value(job_name => k_job_name,argument_position => 2 --quota_abs
                                      ,argument_value => SYS.ANYDATA.convertNumber(80)); 

  DBMS_SCHEDULER.set_resource_constraint 
  (object_name   => k_job_name
  ,resource_name => 'BATCH_UPDATE_LIMIT'
  ,units         => 1);     

  dbms_scheduler.enable(name => k_job_name);
  --dbms_scheduler.disable(name => k_job_name);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END create_update_strava_activity_job;
----------------------------------------------------------------------------------------------------
PROCEDURE create_process_webhook_queue_job 
IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.PROCESS_WEBHOOK_QUEUE_JOB';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.PROCESS_WEBHOOK_QUEUE_CLASS';

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);
  
  create_job_class(k_job_class,'MEDIUM', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => k_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.WEBHOOK_PKG.PROCESS_QUEUE'
    ,enabled => FALSE
    );
  EXCEPTION WHEN e_job_already_exists THEN NULL;
  END;

  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_ACTION', value => 'STRAVA.WEBHOOK_PKG.PROCESS_QUEUE');
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'AUTO_DROP' , value => FALSE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_CLASS' , value => k_job_class); 

  DBMS_SCHEDULER.set_resource_constraint 
  (object_name   => k_job_name
  ,resource_name => 'BATCH_UPDATE_LIMIT'
  ,units         => 1);     

  dbms_scheduler.enable(name => k_job_name);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END create_process_webhook_queue_job;
----------------------------------------------------------------------------------------------------
-- create job to regularly run procedure to purge API log
----------------------------------------------------------------------------------------------------
PROCEDURE create_purge_api_log_job 
IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.PURGE_API_LOG';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.PURGE_API_LOG_CLASS';

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);

  create_job_class(k_job_class,'LOW', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => k_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.STRAVA_HTTP.PURGE_API_LOG'
    ,enabled => FALSE
    );
  EXCEPTION WHEN e_job_already_exists THEN NULL;
  END;
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'AUTO_DROP', value => FALSE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_CLASS', value => k_job_class);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'START_DATE'      
                              ,value => TRUNC(SYSTIMESTAMP AT TIME ZONE 'UTC') + INTERVAL '1' DAY + INTERVAL '15' MINUTE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'REPEAT_INTERVAL' ,value => 'FREQ=DAILY;BYHOUR=0;BYMINUTE=15');
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'NUMBER_OF_ARGUMENTS', value => 0);
  dbms_scheduler.enable(name => k_job_name);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END create_purge_api_log_job;
----------------------------------------------------------------------------------------------------
-- create job to regularly run procedure to purge processed events in event queue
----------------------------------------------------------------------------------------------------
PROCEDURE create_purge_event_queue_job 
IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.PURGE_EVENT_QUEUE';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.PURGE_EVENT_QUEUE_CLASS';

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);

  create_job_class(k_job_class,'LOW', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => k_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.WEBHOOK_PKG.PURGE_EVENT_QUEUE'
    ,enabled => FALSE
    );
  EXCEPTION WHEN e_job_already_exists THEN NULL;
  END;
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'AUTO_DROP', value => FALSE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_CLASS', value => k_job_class);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'START_DATE'      
                              ,value => TRUNC(SYSTIMESTAMP AT TIME ZONE 'UTC') + INTERVAL '1' DAY + INTERVAL '42' MINUTE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'REPEAT_INTERVAL' ,value => 'FREQ=DAILY;BYHOUR=0;BYMINUTE=42');
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'NUMBER_OF_ARGUMENTS', value => 0);
  dbms_scheduler.enable(name => k_job_name);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END create_purge_event_queue_job;
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
PROCEDURE create_renew_strava_tokens_job 
IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.RENEW_STRAVA_TOKENS_JOB';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.RENEW_STRAVA_TOKENS_CLASS';

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);

  create_job_class(k_job_class,'HIGH', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => k_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.STRAVA_HTTP.RENEW_STRAVA_TOKENS'
    ,enabled => FALSE
    );
  EXCEPTION 
    WHEN e_job_already_exists THEN NULL;
  END;
  
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'AUTO_DROP', value => FALSE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_CLASS', value => k_job_class); --because it is important to renew the token
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'REPEAT_INTERVAL', value => 'FREQ=HOURLY;INTERVAL=6');
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'NUMBER_OF_ARGUMENTS', value => 0);
  dbms_scheduler.enable(name => k_job_name);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END create_renew_strava_tokens_job;
----------------------------------------------------------------------------------------------------
PROCEDURE create_get_activity_job 
(p_activity_id activities.activity_id%TYPE
) IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.GET_ACTIVITY_JOB';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.GET_ACTIVITY_CLASS';
  l_job_name VARCHAR2(128 CHAR);

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);

  l_job_name := k_job_name||'_'||p_activity_id;

  create_job_class(k_job_class,'LOW', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => l_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.STRAVA_HTTP.GET_ACTIVITY'
    ,number_of_arguments => 2
    ,start_date => SYSTIMESTAMP AT TIME ZONE 'UTC'
    ,job_class => k_job_class
    ,enabled => FALSE
    ,auto_drop  => TRUE
    );
  EXCEPTION WHEN e_job_already_exists THEN 
    dbms_output.put_line('Job '||l_job_name||' Already Exists');
    dbms_scheduler.disable(name => l_job_name);
    dbms_scheduler.set_attribute(name => l_job_name, attribute => 'AUTO_DROP' , value => TRUE);
    dbms_scheduler.set_attribute(name => l_job_name, attribute => 'JOB_CLASS' , value => k_job_class);
    dbms_scheduler.set_attribute(name => l_job_name, attribute => 'START_DATE', value => SYSTIMESTAMP AT TIME ZONE 'UTC');
  END;

  dbms_scheduler.set_job_anydata_value
  (job_name => l_job_name
  ,argument_position => 1 --activity_id
  ,argument_value => SYS.ANYDATA.convertNumber(p_activity_id)
  );
  dbms_scheduler.set_job_anydata_value
  (job_name => l_job_name
  ,argument_position => 2 --get stream
  ,argument_value => SYS.ANYDATA.convertNumber(1)
  );

  DBMS_SCHEDULER.set_resource_constraint 
  (object_name   => l_job_name
  ,resource_name => 'GET_ACTIVITY_LIMIT'
  ,units         => 1);     
  dbms_scheduler.enable(name => l_job_name);

  dbms_output.put_line('Job '||l_job_name||' Submitted/Enabled');
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN e_job_running THEN
    dbms_output.put_line('Job '||l_job_name||' Running');
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  
END create_get_activity_job;
----------------------------------------------------------------------------------------------------
--create a job to submit jobs to recalculate all activity areas for named job
----------------------------------------------------------------------------------------------------
PROCEDURE create_activity_hsearch_upd_all
IS
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'create_activity_hsearch_upd_all');

  FOR i IN (
    SELECT activity_id
    FROM   activities
    WHERE  processing_status = k3_status_stream_loaded
  ) LOOP
    strava_job.create_activity_hsearch_upd_job(i.activity_id);
  END LOOP;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action); 
END create_activity_hsearch_upd_all;
----------------------------------------------------------------------------------------------------
--create a job to run the proceduce to process all areas requiring hierarchical search
----------------------------------------------------------------------------------------------------
PROCEDURE create_activity_hsearch_upd_all_job 
IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.CREATE_ACTIVITY_HSEARCH_UPD_ALL_JOB';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.CREATE_ACTIVITY_HSEARCH_UPD_ALL_CLASS';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);

  create_job_class(k_job_class,'LOW', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => k_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.STRAVA_JOB.CREATE_ACTIVITY_HSEARCH_UPD_ALL'
    ,enabled => FALSE
    );
  EXCEPTION WHEN e_job_already_exists THEN NULL;
  END;

  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'AUTO_DROP', value => FALSE);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'JOB_CLASS', value => k_job_class);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'START_DATE'      
                              ,value => TRUNC(SYSTIMESTAMP AT TIME ZONE 'UTC') + INTERVAL '1' DAY);
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'REPEAT_INTERVAL' ,value => 'FREQ=DAILY;BYHOUR=3;BYMINUTE=42');
  dbms_scheduler.set_attribute(name => k_job_name, attribute => 'NUMBER_OF_ARGUMENTS', value => 0);
  dbms_scheduler.enable(name => k_job_name);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END create_activity_hsearch_upd_all_job;
----------------------------------------------------------------------------------------------------
--create a job to recalculate activity areas for named job
----------------------------------------------------------------------------------------------------
PROCEDURE create_activity_hsearch_upd_job
(p_activity_id activities.activity_id%TYPE
) IS
  k_job_name  CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.ACTIVITY_HSEARCH_UPD_JOB';
  k_job_class CONSTANT VARCHAR2(128 CHAR) :=    'SYS.ACTIVITY_HSEARCH_UPD_CLASS';

  l_job_name VARCHAR2(128 CHAR);

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);

  l_job_name := k_job_name||'_'||p_activity_id;

  create_job_class(k_job_class,'LOW', p_log_history=>7);
  BEGIN
    dbms_scheduler.create_job   
    (job_name => l_job_name
    ,job_type => 'STORED_PROCEDURE'
    ,job_action => 'STRAVA.STRAVA_SDO.ACTIVITY_HSEARCH_UPD'
    ,number_of_arguments => 1
    ,start_date => SYSTIMESTAMP AT TIME ZONE 'UTC'
    ,job_class => k_job_class
    ,enabled => FALSE
    ,auto_drop  => TRUE
    );
  EXCEPTION WHEN e_job_already_exists THEN 
    dbms_output.put_line('Job '||l_job_name||' Already Exists');
    dbms_scheduler.disable(name => l_job_name);
    dbms_scheduler.set_attribute(name => l_job_name, attribute => 'AUTO_DROP' , value => TRUE);
    dbms_scheduler.set_attribute(name => l_job_name, attribute => 'JOB_CLASS' , value => k_job_class);
    dbms_scheduler.set_attribute(name => l_job_name, attribute => 'START_DATE', value => SYSTIMESTAMP AT TIME ZONE 'UTC');
  END;

  dbms_scheduler.set_job_anydata_value
  (job_name => l_job_name
  ,argument_position => 1 --quota_pct
  ,argument_value => SYS.ANYDATA.convertNumber(p_activity_id)
  );

  DBMS_SCHEDULER.set_resource_constraint 
  (object_name   => l_job_name
  ,resource_name => 'ACTIVITY_HSEARCH_UPD_LIMIT'
  ,units         => 1);     
  dbms_scheduler.enable(name => l_job_name);

  dbms_output.put_line('Job '||l_job_name||' Submitted/Enabled');
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN e_job_running THEN
    dbms_output.put_line('Job '||l_job_name||' Running');
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  
END create_activity_hsearch_upd_job;
----------------------------------------------------------------------------------------------------
END strava_job;
/
show errors

BEGIN
  DBMS_SCHEDULER.create_resource 
  (resource_name    => 'GET_ACTIVITY_LIMIT'
  ,units            => 1
  ,status           => 'ENFORCE_CONSTRAINTS'
  ,constraint_level => 'JOB_LEVEL');
END;
/	  
BEGIN
  DBMS_SCHEDULER.create_resource 
  (resource_name    => 'BATCH_UPDATE_LIMIT'
  ,units            => 1
  ,status           => 'ENFORCE_CONSTRAINTS'
  ,constraint_level => 'JOB_LEVEL');
END;
/	  


BEGIN
  DBMS_SCHEDULER.drop_resource 
  (resource_name    => 'ACTIVITY_HSEARCH_UPD_LIMIT'
  );
END;
/
BEGIN
  DBMS_SCHEDULER.create_resource 
  (resource_name    => 'ACTIVITY_HSEARCH_UPD_LIMIT'
  ,units            => 4
  ,status           => 'ENFORCE_CONSTRAINTS'
  ,constraint_level => 'JOB_LEVEL');
END;
/	  
BEGIN
  DBMS_SCHEDULER.set_attribute
  (name => 'ACTIVITY_HSEARCH_UPD_LIMIT'
  ,attribute => 'UNITS'
  ,value => 4
  );
END;
/

EXECUTE strava_job.create_activity_hsearch_upd_all_job /*task to create a job for each activity*/;
EXECUTE strava_job.create_activity_area_list_upd_all_job /*create job to run task to create all update jobs*/;
EXECUTE strava_job.create_purge_api_log_job;
EXECUTE strava_job.create_purge_event_queue_job;
EXECUTE strava_job.create_renew_strava_tokens_job;
EXECUTE strava_job.create_batch_load_activities_job;
EXECUTE strava_job.create_update_strava_activity_job;
EXECUTE strava_job.create_process_webhook_queue_job;
--EXECUTE dbms_Scheduler.run_job('STRAVA.CREATE_ACTIVITY_HSEARCH_UPD_ALL_JOB',FALSE) /*refresh all activity areas-can take time*/;
--EXECUTE dbms_Scheduler.run_job('STRAVA.ACTIVITY_AREA_LIST_UPD_ALL_JOB',FALSE) /*this runs a job to create the update jobs*/; 
--EXECUTE dbms_Scheduler.run_job('STRAVA.UPDATE_STRAVA_ACTIVTY_JOB',FALSE);
--execute STRAVA.STRAVA_SDO.ACTIVITY_AREA_LIST_UPD_ALL;

--clear screen
--set serveroutput on
--exec STRAVA.STRAVA_HTTP.BATCH_UPDATE_STRAVA_ACTIVITY(100,100);

set echo off
/*
set pages 999 lines 120 trimspool on
clear screen
column client_id format a10
column client_secret format a40
column access_token format a40
column refresh_token format a40
column owner format a8
column user_name format a8
column job_creator format a8
bcolumn job_name format a30
column job_subname format a30
column job_action format a40
column repeat_interval format a40
column job_class format a20
column operation format a10
column status format a10
column raise_Events format a30
column client_id format a16
column program_owner format a8
column program_name format a30
column source format a30
column connect_credential_owner format a8
column connect_credential_name format a30
column credential_owner format a8
column credential_name format a30
column schedule_owner format a8
column schedule_name format a30
column event_queue_owner format a8
column event_queue_name format a30
column event_queue_agent format a30
column event_condition format a30
column event_rule format a30
column destination_owner format a8
column destination format a30
column file_watcher_owner format a8
column file_watcher_name format a30
column session_id format a16
column state format a10
set pages 999 lines 120

select * from dba_scheduler_job_classes 
where service IS NOT NULL
order by resource_consumer_group, job_class_name
/

select * from dba_scheduler_jobs 
where owner = 'STRAVA' 
--AND job_name like 'B%'
ORDER BY 1,2
/
select * from dba_scheduler_running_jobs
where owner = 'STRAVA' 
ORDER BY 1,2
/
select owner, job_name, argument_position, argument_Type
,      SYS.ANYDATA.accessNumber(anydata_value) anydata_value
from   all_scheduler_job_args
where owner = 'STRAVA' --AND job_name = 'RENEW_STRAVA_TOKENS_JOB'
/ 
select * from dba_scheduler_job_log 
where owner = 'STRAVA' --AND job_name = 'RENEW_STRAVA_TOKENS_JOB'
ORDER BY 1 desc,2 FETCH FIRST 50 ROWS ONLY
/
select * from dba_scheduler_job_run_details
where owner = 'STRAVA' --AND job_name = 'RENEW_STRAVA_TOKENS_JOB'
ORDER BY 1 desc,2 
FETCH FIRST 50 ROWS ONLY
/
*/

spool off

--EXECUTE dbms_Scheduler.run_job('STRAVA.CREATE_ACTIVITY_HSEARCH_UPD_ALL_JOB',FALSE);

/*
clear screen
set serveroutput on echo on
EXECUTE dbms_Scheduler.run_job('STRAVA.UPDATE_STRAVA_ACTIVTY_JOB');
*/
