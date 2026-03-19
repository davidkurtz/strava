REM strava_webhook_pkg.sql
clear screen
set echo on
spool strava_webhook_pkg.lst
----------------------------------------------------------------------------------------------------
-- webhook handler package
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE strava.webhook_pkg AS
PROCEDURE handle_post
(p_body IN CLOB
,p_status_code IN OUT NUMBER
);
PROCEDURE handle_get
(p_hub_challenge IN VARCHAR2
,p_verify_token  IN VARCHAR2
,p_response      IN OUT CLOB
,p_status_code   IN OUT NUMBER
,p_message       OUT CLOB 
);
PROCEDURE process_queue;
PROCEDURE purge_event_queue;
END webhook_pkg;
/
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY strava.webhook_pkg AS
----------------------------------------------------------------------------------------------------
k_module CONSTANT VARCHAR2(64 CHAR) := $$PLSQL_UNIT;
----------------------------------------------------------------------------------------------------
-- queue statuses
----------------------------------------------------------------------------------------------------
k0_unprocessed CONSTANT INTEGER := 0;
k1_processed   CONSTANT INTEGER := 1;
k2_superceded  CONSTANT INTEGER := 2;
----------------------------------------------------------------------------------------------------
--this is a webhook set up and it is specified by the user and echoed back by Strava
g_verify_token CONSTANT VARCHAR2(100) := 'PlaceCloud42'; 
----------------------------------------------------------------------------------------------------
e_asset_not_found EXCEPTION; --strava asset not found
PRAGMA EXCEPTION_INIT(e_asset_not_found,-20404);
----------------------------------------------------------------------------------------------------
PROCEDURE handle_post
(p_body IN CLOB
,p_status_code IN OUT NUMBER
) IS
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'handle_post');
  --strava_http.pretty_json(p_body);
  p_status_code := 200;  

  INSERT INTO strava.webhook_events (payload) VALUES (p_body);
  
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION WHEN OTHERS THEN
  p_status_code := 500;
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END handle_post;
----------------------------------------------------------------------------------------------------
PROCEDURE handle_get
(p_hub_challenge IN VARCHAR2
,p_verify_token  IN VARCHAR2
,p_response      IN OUT CLOB
,p_status_code   IN OUT NUMBER
,p_message       OUT CLOB 
) IS
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'handle_gen');

  IF p_verify_token = g_verify_token THEN
    p_response := JSON_OBJECT('hub.challenge' VALUE p_hub_challenge);
	--p_response := p_hub_challenge;
    p_status_code := 200; --ok
	p_message := 'OK';
  ELSE
    p_message := 'Verification Token Failed:'||p_verify_token;
    p_status_code := 403; --forbidden
  END IF;
  
  INSERT INTO strava.webhook_events (payload) 
  VALUES ('handle_get:'||p_hub_challenge||','||p_verify_token||' ('||p_status_code||', '||p_message||')'
  );

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
--EXCEPTION 
--  WHEN OTHERS THEN 
--    p_message := sqlerrm;
--    p_status_code := 403; --forbidden
END handle_get;
----------------------------------------------------------------------------------------------------
PROCEDURE process_queue IS

  l_processing_status INTEGER;
  l_status_msg CLOB;

  l_obj        JSON_OBJECT_T;
  l_keys       JSON_KEY_LIST;
  l_key        VARCHAR2(128 CHAR);
  l_num_keys   INTEGER;
  l_value      CLOB;
  l_sep        VARCHAR2(4 CHAR);
  l_column     VARCHAR2(128 CHAR);
  l_sql        CLOB;

  k_action CONSTANT VARCHAR2(64 CHAR) := 'process_queue';  
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);

  /*delete any webhook events with a subsequent delete event
  UPDATE webhook_events u
  SET    u.processing_status = k2_superceded
  WHERE  u.object_type = 'activity'
  AND    u.processing_status = k0_unprocessed
  AND    u.aspect_type IN('create','update')
  AND EXISTS(
	  SELECT 'x'
	  FROM   webhook_events d
	  WHERE  d.aspect_type = 'delete'
	  AND    d.object_type = 'activity'
	  AND    d.processing_status = k0_unprocessed
	  AND    d.object_id = u.object_id
	  AND    u.id < d.id);
  COMMIT;
  --dbms_output.put_line(k_action||':'||sql%rowcount||' superceded events processing status updated');
  */
  
  --interate requests
  FOR i IN (
    SELECT h.*, a.activity_id
    FROM webhook_events h
	  LEFT OUTER JOIN activities a ON a.activity_id = h.object_id 
    WHERE h.processing_status = k0_unprocessed
	AND   h.object_type = 'activity'
	ORDER BY h.id
    FOR UPDATE OF h.processing_status 
    --SKIP LOCKED
  ) LOOP
    l_processing_status := NULL;  
	l_status_msg := 'ID '||i.id||': '||INITCAP(i.object_type)||' '||i.object_id;
	
    BEGIN
      IF i.aspect_type = 'delete' THEN
	    IF i.activity_id IS NULL THEN --does not exist
		  l_status_msg := l_status_msg||' does not exist.';
		  l_processing_status := k2_superceded;
		ELSE --not already deleted
          DELETE FROM activities WHERE activity_id = i.activity_id;
		  l_status_msg := l_status_msg||' deleted. '||sql%rowcount||' rows deleted.';
		  l_processing_status := k1_processed;
	    END IF;

	  ELSIF i.aspect_type = 'create' THEN
	    IF i.activity_id IS NULL THEN --not already created
		  BEGIN
  	        strava_http.get_activity(i.object_id,p_get_stream=>TRUE);
		    l_processing_status := k1_processed;
		    l_status_msg := l_status_msg||' extracted from Strava.';
		  EXCEPTION
		    WHEN e_asset_not_found THEN
     	      l_status_msg := l_status_msg||'. '||sqlerrm;
		      l_processing_status := ABS(sqlcode);
		  END;
		ELSE
		  l_processing_status := k2_superceded;
		  l_status_msg := l_status_msg||' already created. Skipped.';
		END IF;

	  ELSIF i.aspect_type = 'update' THEN
	    IF i.activity_id IS NULL THEN --not already created so create it
		  BEGIN
  	  	    strava_http.get_activity(i.object_id,p_get_stream=>TRUE);
		    l_processing_status := k1_processed;
	        l_status_msg := l_status_msg||' extracted from Strava.';
		  EXCEPTION
		    WHEN e_asset_not_found THEN
     	      l_status_msg := l_status_msg||'. '||sqlerrm;
		      l_processing_status := ABS(sqlcode);
		  END;
		ELSE
          -- Parse JSON
          l_obj := JSON_OBJECT_T.parse(i.updates);
          -- Get all keys
          l_keys := l_obj.get_keys;
		  l_num_keys := l_keys.COUNT;
		  IF l_num_keys > 0 THEN 
            l_status_msg := l_status_msg||': Updating '||l_num_keys||' fields';
		    l_sql := 'UPDATE ACTIVITIES ';
		    l_sep := 'SET ';
            FOR i IN 1 .. l_keys.COUNT LOOP
              l_key := lower(l_keys(i));
              -- Get value as string
              l_value := l_obj.get_string(l_key);
              -- Process only specific keys
              IF l_key IN ('private', 'visibility','title','type') THEN
 		        IF l_key = 'title' THEN 
			      l_column := 'name';
			    ELSE 
				  l_column := l_key;
				END IF;
                --DBMS_OUTPUT.put_line('Processing: ' || l_key || ' = ' || l_value);
	            l_sql := l_sql||l_sep||l_column||' = '''||l_value||'''';
              ELSE
			    NULL;
                --DBMS_OUTPUT.put_line('Skipping: ' || l_key);
              END IF;
	          l_sep := ', ';
            END LOOP;
			l_sql := l_sql||' WHERE activity_id = :1';
			--dbms_output.put_line(k_action||':'||l_sql);
			EXECUTE IMMEDIATE l_sql USING i.activity_id;
			l_processing_status := k1_processed;
			l_status_msg := l_status_msg||': '||l_sql;

		  ELSE 
   		    UPDATE activities
		    SET processing_status = 1 --force activity to full reprocess
		    WHERE activity_id = i.activity_id;
		    strava_http.get_activity(i.object_id,p_get_stream=>TRUE);
			l_processing_status := k1_processed;
   	        l_status_msg := l_status_msg||' re-extracted from Strava.';
		  END IF;
	    END IF;

	  ELSE 	   
	    l_status_msg := l_status_msg||'. Unknown action ';
	    l_processing_status := 0;  
      END IF;
      dbms_output.put_line(l_status_msg);

      IF l_processing_status IS NOT NULL THEN

        UPDATE strava.webhook_events
        SET processing_status = l_processing_status
	    ,   status_msg = l_status_msg 
        WHERE id = i.id;

	  END IF;
	EXCEPTION
      WHEN OTHERS THEN
	    dbms_output.put_line(l_status_msg);
	    l_status_msg := sqlerrm;
		l_processing_status := sqlcode;
        UPDATE strava.webhook_events
        SET processing_status = l_processing_status
		,   status_msg = l_status_msg
        WHERE id = i.id;
	  
	END;
  END LOOP;
  COMMIT;
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END process_queue;
----------------------------------------------------------------------------------------------------
-- purge webhook event queue processed events 7 day after last update
----------------------------------------------------------------------------------------------------
PROCEDURE purge_event_queue IS
  l_num_rows INTEGER := 0;
  l_max_date TIMESTAMP WITH TIME ZONE := trunc(SYSTIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '7' DAY;
  
  k_action CONSTANT VARCHAR2(64 CHAR) := 'purge_event_queue';  
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);

  /*delete processed webhook events older than 1 week*/
  DELETE webhook_events u
  WHERE  (processing_status > 0 OR (processing_status = 0 AND aspect_type IS NULL))
  AND    (last_updated < l_max_date
  --AND    event_time < l_max_date
  AND    received_at < l_max_date)
  RETURNING count(*) INTO l_num_rows;
  
  dbms_output.put_line(k_action||':'||l_num_rows||' processed events purged from queue up to '||l_max_date);
  COMMIT;
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END purge_event_queue;
----------------------------------------------------------------------------------------------------
END webhook_pkg;
/
show errors
spool off