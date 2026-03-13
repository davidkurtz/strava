REM strava_sig.sql
clear screen
set echo on
spool strava_sig.lst

CREATE OR REPLACE PACKAGE strava.strava_sig AS 

FUNCTION activities_signature
(p_activities IN OUT activities%rowtype
,p_action VARCHAR2 --(C)heck, (S)et, (U)pdate
) RETURN BOOLEAN;

END strava_sig;
/
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE BODY strava.strava_sig AS 
----------------------------------------------------------------------------------------------------
k_module        CONSTANT VARCHAR2(64 CHAR) := $$PLSQL_UNIT;
----------------------------------------------------------------------------------------------------
FUNCTION my_crypto (p_string CLOB) 
RETURN VARCHAR2 IS 
BEGIN
  RETURN sys.DBMS_CRYPTO.hash(UTL_RAW.cast_to_raw(p_string),DBMS_CRYPTO.hash_sh256);
END my_crypto;
----------------------------------------------------------------------------------------------------
FUNCTION activities_crypto(p_activities activities%rowtype
) RETURN VARCHAR2 IS 
BEGIN
  RETURN my_crypto(p_activities.activity_id
                 ||p_activities.name
                 ||p_activities.description
                 ||p_activities.distance_km
                 ||p_activities.elapsed_time
                 ||p_activities.moving_time
                 ||p_activities.elevation_gain
				 ||p_activities.photo_count
				 ||p_activities.num_pts
				 );
END activities_crypto;
----------------------------------------------------------------------------------------------------
FUNCTION activities_signature
(p_activities IN OUT activities%rowtype
,p_action VARCHAR2 --(C)heck, (S)et, (U)pdate
) RETURN BOOLEAN IS 
  l_signature VARCHAR2(64 CHAR);
  l_sigmatch BOOLEAN := FALSE;

  l_module   VARCHAR2(64 CHAR);
  l_action   VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'activities_signature');

  --dbms_output.put_line('XXX1');
  l_signature := activities_crypto(p_activities);
  ---dbms_output.put_line('XXX2');

  --check to see if signature is the same
  IF l_signature = p_activities.signature THEN
    l_sigmatch := TRUE;
  END IF;
  
  dbms_output.put_line('activity_id '||p_activities.activity_id||' signature matched:'||CAST(l_sigmatch AS VARCHAR2));

  IF p_action = 'C' THEN --check signature and return true in matched
    NULL;
  ELSIF p_action = 'S' THEN --set signature in row type
    p_activities.signature := l_signature;
  ELSIF p_action = 'U' THEN --set signature in row type and update record
    p_activities.signature := l_signature;

    UPDATE activities
	SET ROW = p_activities
	WHERE  activity_id = p_activities.activity_id;

  END IF;
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RETURN l_sigmatch;
EXCEPTION WHEN OTHERS THEN
  dbms_output.put_line(sqlerrm);
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END activities_signature;
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
END strava_sig;
----------------------------------------------------------------------------------------------------
/
spool off

----------------------------------------------------------------------------------------------------
--refresh all signatures after updating signature function
----------------------------------------------------------------------------------------------------
LOCK TABLE ACTIVITIES IN EXCLUSIVE MODE;
set serveroutput on
DECLARE
  CURSOR c_activities IS
  SELECT * FROM activities FOR UPDATE;
  l_matched BOOLEAN;
BEGIN
  FOR r_activities IN c_activities LOOP
    l_matched := strava_sig.activities_signature(r_activities,'S');
    UPDATE activities
    SET signature =r_activities.signature
    WHERE activity_id = r_activities.activity_id;
  END LOOP;
  COMMIT;
END;
/