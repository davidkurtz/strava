REM strava_http.sql
clear screen
set echo on
spool strava_http.lst

----------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE strava.strava_http AS
----------------------------------------------------------------------------------------------------
PROCEDURE print_clob(p_clob CLOB);
PROCEDURE pretty_json(p_raw_json CLOB);
FUNCTION iso8601_utc(p_iso8601_utc VARCHAR2) RETURN TIMESTAMP WITH TIME ZONE;
FUNCTION clean_clob(p_clob IN CLOB) RETURN CLOB;
FUNCTION clean_string(p_clob IN CLOB) RETURN CLOB;

FUNCTION http_request 
(p_url IN VARCHAR2
,p_redirect IN NUMBER DEFAULT NULL
) RETURN CLOB;

FUNCTION strava_http_request
(p_url VARCHAR2
,p_req_type VARCHAR2 DEFAULT 'GET'
,p_put_body CLOB     DEFAULT NULL --e.g. 'description=Updated from PL/SQL'
) RETURN CLOB;
----------------------------------------------------------------------------------------------------
PROCEDURE batch_load_activities
(p_quota_pct           NUMBER DEFAULT 80
,p_quota_abs           NUMBER DEFAULT 80
);

PROCEDURE batch_update_strava_activity
(p_quota_pct           NUMBER DEFAULT 80
,p_quota_abs           NUMBER DEFAULT 80
);

PROCEDURE get_athlete_activities
(p_before              IN TIMESTAMP WITH TIME ZONE DEFAULT NULL
,p_after               IN TIMESTAMP WITH TIME ZONE DEFAULT NULL
,p_page                INTEGER DEFAULT NULL
,p_per_page            INTEGER DEFAULT NULL
);

PROCEDURE get_activity
(p_activity_id         activities.activity_id%TYPE
,p_get_stream          IN BOOLEAN DEFAULT TRUE
,p_include_all_efforts IN BOOLEAN DEFAULT FALSE
);

PROCEDURE get_activity_gpx
(p_activity_id         activities.activity_id%TYPE
);

PROCEDURE get_activity_stream_id
(p_activity_id         activities.activity_id%TYPE
);

PROCEDURE get_activity_stream
(p_activities          IN OUT activities%ROWTYPE
);

PROCEDURE get_gear
(p_gear_id  IN VARCHAR2
);

PROCEDURE purge_api_log;

PROCEDURE renew_strava_tokens
(p_force               BOOLEAN DEFAULT FALSE
);

PROCEDURE update_strava_activity
(p_activity_id         IN activities.activity_id%TYPE
);

PROCEDURE create_webhook
(p_callback_url CLOB
);

----------------------------------------------------------------------------------------------------
END strava_http;
/
show errors
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY strava.strava_http AS
----------------------------------------------------------------------------------------------------
--package constants
----------------------------------------------------------------------------------------------------
k_module                 CONSTANT VARCHAR2(64 CHAR) := $$PLSQL_UNIT;
k_strava_url             CONSTANT VARCHAR2(32 CHAR) := 'https://www.strava.com/';
k_strava_api             CONSTANT VARCHAR2(32 CHAR) := 'https://www.strava.com/api/v3/';
k_creator                CONSTANT VARCHAR2(64 CHAR) := 'GFCStavaPlaceCloud';
k_iso8601                CONSTANT VARCHAR2(32 CHAR) := 'YYYY-MM-DD"T"HH24:MI:SS"Z"';
k_iso8601_tzr            CONSTANT VARCHAR2(32 CHAR) := 'YYYY-MM-DD"T"HH24:MI:SS"Z" TZR';
k_max_athlete_activities CONSTANT INTEGER := 200;
----------------------------------------------------------------------------------------------------
--special characters
----------------------------------------------------------------------------------------------------
k_lf                     CONSTANT VARCHAR2(1 CHAR)  := CHR(10);
k_cr                     CONSTANT VARCHAR2(1 CHAR)  := CHR(13);
k_ampersand              CONSTANT VARCHAR2(1 CHAR)  := CHR(38);
----------------------------------------------------------------------------------------------------
--spatial constants
----------------------------------------------------------------------------------------------------
k_wgs84         CONSTANT INTEGER := 4326;
k_geom_line     CONSTANT INTEGER := 2002;
----------------------------------------------------------------------------------------------------
-- access tokens
----------------------------------------------------------------------------------------------------
g_access_token  VARCHAR2(4000);
g_refresh_token VARCHAR2(4000);
g_client_id     VARCHAR2(100 CHAR);
g_client_secret VARCHAR2(100 CHAR);
g_expires_at    TIMESTAMP;
----------------------------------------------------------------------------------------------------
-- strava usage limit tracking
----------------------------------------------------------------------------------------------------
g_short_read_limit INTEGER;
g_long_read_limit  INTEGER;
g_short_read_usage INTEGER;
g_long_read_usage  INTEGER;
g_short_all_limit  INTEGER;
g_long_all_limit   INTEGER;
g_short_all_usage  INTEGER;
g_long_all_usage   INTEGER;
g_usage_ts         TIMESTAMP WITH TIME ZONE;
----------------------------------------------------------------------------------------------------
--Activity Statuses
----------------------------------------------------------------------------------------------------
k0_status_undefined           CONSTANT INTEGER := 0;
k1_status_athlete_loaded      CONSTANT INTEGER := 1;
k2_status_activity_loaded     CONSTANT INTEGER := 2;
k3_status_stream_loaded       CONSTANT INTEGER := 3;
k4_status_areas_processed     CONSTANT INTEGER := 4;
k5_status_area_list_updated   CONSTANT INTEGER := 5;
k6_status_description_updated CONSTANT INTEGER := 6;
k9_do_not_process             CONSTANT INTEGER := 9;
----------------------------------------------------------------------------------------------------
e_job_does_not_exists EXCEPTION;
PRAGMA EXCEPTION_INIT(e_job_does_not_exists,-27476);
e_http_request_failed EXCEPTION;
PRAGMA EXCEPTION_INIT(e_http_request_failed,-29273);
e_too_many_open_requests EXCEPTION;
PRAGMA EXCEPTION_INIT(e_too_many_open_requests,-29270);
e_json_null_self EXCEPTION;
PRAGMA EXCEPTION_INIT(e_json_null_self,-30625);
e_xml_parse_fail EXCEPTION;
PRAGMA EXCEPTION_INIT(e_xml_parse_fail,-31011);
e_json_syntax_error EXCEPTION; --ORA-40441: JSON syntax error
PRAGMA EXCEPTION_INIT(e_json_syntax_error,-40441);
e_dv_insert EXCEPTION; --ORA-42692: Cannot insert into JSON Relational Duality View
PRAGMA EXCEPTION_INIT(e_dv_insert,-42692);
----------------------------------------------------------------------------------------------------
FUNCTION booltochar(p_boolean BOOLEAN)
RETURN VARCHAR2 IS
BEGIN
  RETURN CAST(p_boolean AS VARCHAR2);
/*
  RETURN CASE WHEN p_boolean THEN 'true'
              WHEN NOT p_boolean THEN 'false' END;
*/
END booltochar;
----------------------------------------------------------------------------------------------------
FUNCTION iso8601_utc(p_iso8601_utc VARCHAR2) 
RETURN TIMESTAMP WITH TIME ZONE IS
BEGIN
  RETURN to_timestamp_tz(p_iso8601_utc||' UTC',k_iso8601_tzr);
END iso8601_utc;
----------------------------------------------------------------------------------------------------
FUNCTION iso8601_tz (p_iso8601_local VARCHAR2
                    ,p_strava_timezone VARCHAR2)
RETURN TIMESTAMP WITH TIME ZONE IS
  l_tzhm VARCHAR2(6 CHAR);
  l_tzr  VARCHAR2(32 CHAR);
  l_timestamp_localtz TIMESTAMP WITH TIME ZONE;
BEGIN
  l_tzhm := REGEXP_SUBSTR(p_strava_timezone,'[^\(^\)]+',5,1,'i');
  l_tzr  := REGEXP_SUBSTR(p_strava_timezone,'[^\(^\)]+',1,2,'i');
  
  IF l_tzr IS NOT NULL THEN
    l_timestamp_localtz := to_timestamp_tz(p_iso8601_local||' '||l_tzr ,k_iso8601||' TZR');
  ELSE
    l_timestamp_localtz := to_timestamp_tz(p_iso8601_local||' '||l_tzhm,k_iso8601||' TZH:TZM');
  END IF;

  RETURN l_timestamp_localtz;
END iso8601_tz;
----------------------------------------------------------------------------------------------------
FUNCTION clean_clob(p_clob IN CLOB) 
RETURN CLOB IS
BEGIN
-- Remove non-printable control characters
--RETURN REGEXP_REPLACE(p_clob,'[[:cntrl:]&&[^'||CHR(9)||CHR(10)||CHR(13)||']]','');
  RETURN REGEXP_REPLACE(p_clob,'[^[:print:]]','');
END clean_clob;
----------------------------------------------------------------------------------------------------
FUNCTION escape_form_value(p_input IN CLOB)
RETURN VARCHAR2 IS
  l_pos INTEGER;
  
  l_input CLOB;
  l_return CLOB;
  
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'escape_form_value');
 
  l_input := p_input;
  --l_input := CONVERT(p_input, 'AL32UTF8', 'WE8MSWIN1252');
  --l_input := REGEXP_REPLACE(l_input, '[^[:print:][:cntrl:]]', ''); 
  --l_input := REPLACE(l_input,CHR(13),'');
  --l_input := REPLACE(l_input,chr(49840),'');
  --l_input := REPLACE(l_input,chr(14845090),'');
  --dbms_output.put_line('Input='||l_input);
  l_pos := INSTR(l_input,'=');
  --dbms_output.put_line('Position='||l_pos);  

  IF l_pos > 0 THEN
    l_return := SUBSTR(l_input,1,l_pos)||UTL_URL.escape(SUBSTR(l_input,l_pos+1),TRUE,'UTF-8');
  ELSE
    l_return := UTL_URL.escape(l_input,TRUE,'UTF-8');
  END IF;
  --dbms_output.put_line('return1='||l_return);
  --l_return := REPLACE(l_return, k_lf, '%0A'); -- line feed
  --dbms_output.put_line('return3='||l_return);
  
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RETURN l_return;
END escape_form_value;
----------------------------------------------------------------------------------------------------
FUNCTION normalize_to_utf8
(p_text       CLOB
,p_src_charset VARCHAR2 DEFAULT 'WE8MSWIN1252'  -- only used if conversion is needed
) RETURN CLOB IS
  l_utf8       CLOB;
  l_invalid    BOOLEAN := FALSE;
BEGIN
  -- 1. Quick check for "garbled" UTF-8 bytes:
  -- non-printable replacement characters (�) or sequences like â, Ã indicate wrong encoding
  IF REGEXP_LIKE(p_text, '[\xC2-\xF4][\x80-\xBF]+') THEN
    l_invalid := TRUE;
  END IF;

  -- 2. If we detect invalid sequences, convert
  IF l_invalid THEN
    l_utf8 := CONVERT(p_text, 'AL32UTF8', p_src_charset);
  ELSE
    l_utf8 := p_text;  -- already fine, leave untouched
  END IF;

  RETURN l_utf8;
EXCEPTION WHEN OTHERS THEN
  -- fallback: return original text if conversion fails
  RETURN p_text;
END normalize_to_utf8;
----------------------------------------------------------------------------------------------------
-- clean false characters from description string
----------------------------------------------------------------------------------------------------
FUNCTION clean_string
(p_clob IN CLOB
) RETURN CLOB is
  l_pos1 INTEGER;
  l_pos2 INTEGER;
  l_clob CLOB;
  
  k_action CONSTANT VARCHAR2(64 CHAR) := 'clean_string';
  k_tm CONSTANT VARCHAR2(1 CHAR) := UNISTR('\2122');
  k_deg CONSTANT VARCHAR2(1 CHAR) := UNISTR('\00b0');
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
--
  l_clob := p_clob;
  --dbms_output.put_line('Before:'||l_clob);
  
  IF p_clob LIKE '%Weather Impact%' THEN
    --fix trademark symbol
	l_clob := regexp_replace(l_clob,'Weather Impact[^S]{3,}:'
                            ,'Weather Impact'||k_tm||':'
							,1,1);

    --fix incorrect characters in front of degrees C
    l_pos1 := regexp_instr(l_clob,'Temp:[ -.[:digit:]]+ ',1,1,1)-1;
    l_pos2 := regexp_instr(l_clob,'Temp:[ -.[:digit:]]+[^[:space:]]+[CF]',1,1,1)-1;
	IF l_pos1>0 and l_pos2>0 AND l_pos2 > l_pos1 THEN
      l_clob := RTRIM(substr(l_clob,1,l_pos1))||' '||k_deg||substr(l_clob,l_pos2);
	END IF;
	--dbms_output.put_line('After:'||l_clob);
  ELSIF l_clob like '%Precip:%END%PlaceCloud%' and not l_clob like '%Weather Impact%' THEN -- no weather impact string
    l_pos2 := regexp_instr(l_clob,'-- PlaceCloud --',1,1);
    l_pos1 := regexp_instr(l_clob,'-- END --',1,1);
    IF l_pos1 > 0 and l_pos2 > 0 AND l_pos1 < l_pos2 THEN
      l_clob := SUBSTR(l_clob,l_pos2);
    END IF;
	--dbms_output.put_line('After:'||l_clob);
  END IF;
--
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RETURN l_clob;
END clean_string;
----------------------------------------------------------------------------------------------------
PROCEDURE print_clob(p_clob CLOB) IS 
  l_length INTEGER;
BEGIN
  l_length := DBMS_LOB.getlength(p_clob);
  --DBMS_OUTPUT.put_line('Length='||l_length);
  -- Output safely (chunked)
  FOR i IN 0 .. CEIL(l_length / 32767) - 1 LOOP
    DBMS_OUTPUT.put_line(
      DBMS_LOB.substr(p_clob, 32767, i * 32767 + 1)
    );
  END LOOP;
END print_clob;
----------------------------------------------------------------------------------------------------
PROCEDURE pretty_json(p_raw_json CLOB) IS
  l_json        JSON_ELEMENT_T;
  l_pretty_json CLOB;
BEGIN
  -- Parse JSON from CLOB
  --l_json := JSON_ELEMENT_T.parse(p_raw_json);
  -- Pretty-print to CLOB
  --l_pretty_json := l_json.to_clob(pretty => TRUE);
  select JSON_SERIALIZE(p_raw_json returning clob PRETTY) into l_pretty_json from dual;
  --l_pretty_json := p_raw_json;  
  print_clob(l_pretty_json);
END pretty_json;
----------------------------------------------------------------------------------------------------
PROCEDURE api_log 
(p_url         VARCHAR2
,p_req_type    VARCHAR2 
,p_http_status NUMBER
) IS
  PRAGMA AUTONOMOUS_TRANSACTION;
  k_action CONSTANT VARCHAR2(64 CHAR) := 'api_log';  
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);

  INSERT INTO api_log
  (request_time, req_type, url, http_status, short_read_usage, long_read_usage, short_all_usage, long_all_usage)
  VALUES
  (SYSTIMESTAMP AT TIME ZONE 'UTC', p_req_type, p_url, p_http_status, g_short_read_usage, g_long_read_usage, g_short_all_usage, g_long_all_usage);
  commit;
  
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END api_log;
----------------------------------------------------------------------------------------------------
PROCEDURE api_log_usage
IS
  l_ts TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP AT TIME ZONE 'UTC';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'api_log_usage');

  IF g_short_read_limit IS NULL THEN
    g_short_read_limit := 100;
  END IF;
  IF g_long_read_limit IS NULL THEN
    g_long_read_limit := 1000;
  END IF;
  IF g_short_all_limit IS NULL THEN
    g_short_all_limit := 200;
  END IF;
  IF g_long_all_limit IS NULL THEN
    g_long_all_limit := 2000;
  END IF;
  IF g_usage_ts IS NULL THEN
    g_usage_ts := l_ts;
  END IF;

  BEGIN
    WITH l as (
      SELECT request_time, short_read_usage, long_read_usage, short_all_usage, long_all_usage
	  FROM   api_log 
      WHERE  short_read_usage is not null 
	  OR     long_read_usage is not null
	  OR     short_all_usage is not null 
	  OR     long_all_usage is not null
      ORDER BY request_time desc nulls last
      FETCH FIRST 1 ROWS ONLY
    )
    SELECT LEAST(g_short_read_limit,short_read_usage) short_read_usage
    ,      LEAST(g_long_read_limit,long_read_usage) long_read_usage
    ,      LEAST(g_short_all_limit,short_all_usage) short_all_usage
    ,      LEAST(g_long_all_limit,long_all_usage) long_all_usage
	,      request_time
	INTO g_short_read_usage, g_long_read_usage, g_short_all_usage, g_long_all_usage, g_usage_ts
    FROM l;
  EXCEPTION WHEN no_data_found THEN
    g_short_read_usage := 0;
	g_long_read_usage := 0;
    g_short_all_usage := 0;
	g_long_all_usage := 0;
	g_usage_ts := SYSTIMESTAMP AT TIME ZONE 'UTC';
  END;
  
  IF g_usage_ts < l_ts THEN 
    g_long_all_usage := 0;
	g_long_read_usage := 0;
  END IF;
  l_ts := TRUNC(l_ts, 'HH24') + NUMTODSINTERVAL(FLOOR(EXTRACT(MINUTE FROM l_ts) / 15) * 15, 'MINUTE');
  IF g_usage_ts < l_ts THEN
    g_short_all_usage := 0;
	g_short_read_usage := 0;
  END IF;

  DBMS_OUTPUT.put_line('API Log:15-min read usage: ' || g_short_read_usage || '/' || g_short_read_limit
                            ||', 15-min all usage: ' || g_short_all_usage || '/' || g_short_all_limit
                            ||', daily read usage: ' || g_long_read_usage || '/' || g_long_read_limit
                            ||', daily all usage: ' || g_long_all_usage || '/' || g_long_all_limit);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END api_log_usage;
----------------------------------------------------------------------------------------------------
FUNCTION http_request 
(p_url IN VARCHAR2
,p_redirect IN NUMBER
) RETURN CLOB IS
  l_req    UTL_HTTP.req;
  l_resp   UTL_HTTP.resp;
  l_buffer VARCHAR2(32767);
  l_clob   CLOB;
  l_header_name   VARCHAR2(256 CHAR);
  l_header_value  VARCHAR2(1024 CHAR);

  k_action CONSTANT VARCHAR2(64 CHAR) := 'http_request';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);

  dbms_output.put_line('URL:'||p_url);
  l_req := UTL_HTTP.begin_request(p_url/*, 'GET', 'HTTP/1.1'*/);
   
  IF p_redirect >= 0 THEN --restrict http redirect - mainly for debug
    UTL_HTTP.set_follow_redirect(l_req, p_redirect);
  END IF;

  --UTL_HTTP.set_body_charset('UTF-8');
  l_resp := UTL_HTTP.get_response(l_req);

  IF l_resp.status_code IN(301,302,303,307,308) THEN
    UTL_HTTP.get_header_by_name(l_resp, 'Location',l_header_value,1); --get redirection URL in header
    dbms_output.put_line(l_header_value);
  End if;

  DBMS_LOB.createtemporary(l_clob, TRUE);
  LOOP
    DECLARE 
      l_buf VARCHAR2(32767);
    BEGIN
      UTL_HTTP.read_text(l_resp, l_buf, 32767);
      DBMS_LOB.writeappend(l_clob, LENGTH(l_buf), l_buf);
    EXCEPTION 
      WHEN UTL_HTTP.end_of_body THEN EXIT; 
    END;
  END LOOP;
  UTL_HTTP.end_response(l_resp);
  
  -- Optional: fix common encoding issues
  --l_clob := CONVERT(l_clob, 'AL32UTF8', 'WE8MSWIN1252');
  -- Optional: remove illegal characters that break JSON
  --l_clob := REGEXP_REPLACE(l_clob, '[^[:print:]\r\n\t]', '');

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RETURN l_clob;

EXCEPTION 
  WHEN e_too_many_open_requests THEN
    UTL_HTTP.end_response(l_resp);
    dbms_output.put_line(k_action||':'||sqlerrm||':Too Many Open Requests');
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
  WHEN e_http_request_failed THEN
    /*list all headers*/
    FOR i IN 1 .. UTL_HTTP.get_header_count(l_resp) LOOP
      UTL_HTTP.get_header(l_resp, i, l_header_name, l_header_value);
      DBMS_OUTPUT.put_line(i ||':'|| l_header_name || ':' || l_header_value);
    END LOOP;/**/
  
    UTL_HTTP.end_response(l_resp);
    dbms_output.put_line(k_action||':'||sqlerrm);
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
  WHEN OTHERS THEN
    UTL_HTTP.end_response(l_resp);
    dbms_output.put_line(k_action||':'||sqlerrm);
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END http_request;
----------------------------------------------------------------------------------------------------
FUNCTION strava_http_request
(p_url VARCHAR2
,p_req_type VARCHAR2 DEFAULT 'GET'
,p_put_body CLOB     DEFAULT NULL --e.g. 'description=Updated from PL/SQL'
) RETURN CLOB IS
  l_req      UTL_HTTP.req;
  l_resp     UTL_HTTP.resp;
  l_clob     CLOB;

  --header variables
  --i               INTEGER;
  l_header_name   VARCHAR2(256 CHAR);
  l_header_value  VARCHAR2(1024 CHAR);
  l_header_body   CLOB;
  
  e_invalid_http_method EXCEPTION;

  k_action CONSTANT VARCHAR2(64 CHAR) := 'strava_http_request';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  
  IF p_req_type IN('GET','PUT','POST') THEN 
    NULL;
  ELSE
    RAISE e_invalid_http_method;
  END IF;

  l_req := UTL_HTTP.begin_request(p_url, p_req_type, 'HTTP/1.1');
  dbms_output.put_line(p_req_type||' '||p_url);
  UTL_HTTP.set_header(l_req, 'Authorization', 'Bearer ' || g_access_token);
  utl_http.set_header(l_req, 'Accept-Charset', 'UTF-8');
  --UTL_HTTP.set_body_charset('UTF-8');
  
  IF p_req_type = 'PUT' THEN
    UTL_HTTP.set_header(l_req, 'Content-Type', 'application/x-www-form-urlencoded');
    IF p_put_body IS NOT NULL THEN   -- Body
	  l_header_body := escape_form_value(p_put_body);
	  UTL_HTTP.set_header(l_req, 'Content-Length', LENGTH(l_header_body));
      --dbms_output.put_line('Body:'||l_header_body||'('||LENGTH(l_header_body)||')');
      UTL_HTTP.write_text(l_req, l_header_body);
	END IF;
  END IF;

  l_resp := UTL_HTTP.get_response(l_req);
  --dbms_output.put_line('http2-'||l_resp.status_code);

  /*list all headers
  FOR i IN 1 .. UTL_HTTP.get_header_count(l_resp) LOOP
    UTL_HTTP.get_header(l_resp, i, l_header_name, l_header_value);
    DBMS_OUTPUT.put_line(i ||':'|| l_header_name || ':' || l_header_value);
  END LOOP;/**/
  
  -- Read usage limit headers
    BEGIN
      UTL_HTTP.get_header_by_name(l_resp, 'x-readratelimit-limit', l_header_value);
	  IF l_header_value IS NOT NULL THEN
        --dbms_output.put_line('Header:'||l_header_value);
        g_short_read_limit := REGEXP_SUBSTR(l_header_value, '[^,]+', 1, 1);
        g_long_read_limit  := REGEXP_SUBSTR(l_header_value, '[^,]+', 1, 2);
      END IF;
	EXCEPTION WHEN e_http_request_failed THEN NULL;
	END;
    BEGIN
      UTL_HTTP.get_header_by_name(l_resp, 'x-readratelimit-usage', l_header_value);
	  IF l_header_value IS NOT NULL THEN
        --dbms_output.put_line('Header:'||l_header_value);
        g_short_read_usage := REGEXP_SUBSTR(l_header_value, '[^,]+', 1, 1);
        g_long_read_usage  := REGEXP_SUBSTR(l_header_value, '[^,]+', 1, 2);
	  END IF;
	EXCEPTION WHEN e_http_request_failed THEN NULL;
	END;
  --IF p_req_type = 'PUT' THEN
    BEGIN
      UTL_HTTP.get_header_by_name(l_resp, 'x-ratelimit-limit', l_header_value);
	  IF l_header_value IS NOT NULL THEN
        --dbms_output.put_line('Header:'||l_header_value);
        g_short_all_limit := REGEXP_SUBSTR(l_header_value, '[^,]+', 1, 1);
        g_long_all_limit  := REGEXP_SUBSTR(l_header_value, '[^,]+', 1, 2);
      END IF;
	EXCEPTION WHEN e_http_request_failed THEN NULL;
    END;
    BEGIN
      UTL_HTTP.get_header_by_name(l_resp, 'x-ratelimit-usage', l_header_value);
	  IF l_header_value IS NOT NULL THEN
        --dbms_output.put_line('Header:'||l_header_value);
        g_short_all_usage := REGEXP_SUBSTR(l_header_value, '[^,]+', 1, 1);
        g_long_all_usage  := REGEXP_SUBSTR(l_header_value, '[^,]+', 1, 2);
	  END IF;
	EXCEPTION WHEN e_http_request_failed THEN NULL;
    END;
  --END IF;
  g_usage_ts := SYSTIMESTAMP AT TIME ZONE 'UTC';
  DBMS_OUTPUT.put_line('API Log:15-min read usage: ' || g_short_read_usage || '/' || g_short_read_limit
                            ||', 15-min all usage: ' || g_short_all_usage || '/' || g_short_all_limit
                            ||', daily read usage: ' || g_long_read_usage || '/' || g_long_read_limit
                            ||', daily all usage: ' || g_long_all_usage || '/' || g_long_all_limit);

  api_log(p_url, p_req_type, l_resp.status_code);

  IF l_resp.status_code = 200 THEN
    NULL; --ok
  ELSIF l_resp.status_code = 401 THEN
    RAISE_APPLICATION_ERROR(-20401,'HTTP 401:Unauthorized');
  ELSIF l_resp.status_code = 403 THEN
    RAISE_APPLICATION_ERROR(-20403,'HTTP 403:Forbidden; you cannot access');
  ELSIF l_resp.status_code = 404 THEN
    RAISE_APPLICATION_ERROR(-20404,'HTTP $04: Not found; the requested asset does not exist, or you are not authorized to see it');
  ELSIF l_resp.status_code = 429 THEN
    RAISE_APPLICATION_ERROR(-20429,'HTTP 429: Too many requests, please check https://www.strava.com/settings/api');
  ELSIF l_resp.status_code = 500 THEN
    RAISE_APPLICATION_ERROR(-20500,'HTTP 500: Strava is having issues, please check https://status.strava.com');
  END IF;

  DBMS_LOB.createtemporary(l_clob, TRUE);
  LOOP
    DECLARE 
	  l_buf VARCHAR2(32767);
    BEGIN
      UTL_HTTP.read_text(l_resp, l_buf, 32767);
	  DBMS_LOB.writeappend(l_clob, LENGTH(l_buf), l_buf);
    EXCEPTION 
      WHEN UTL_HTTP.end_of_body THEN EXIT; 
    END;
  END LOOP;
    
  UTL_HTTP.end_response(l_resp);
 
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
  RETURN l_clob;

EXCEPTION 
  WHEN e_too_many_open_requests THEN
    UTL_HTTP.end_response(l_resp);
	dbms_output.put_line(k_action||':'||sqlerrm||':Too Many Open Requests');
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
	RAISE;
  WHEN e_http_request_failed THEN
    UTL_HTTP.end_response(l_resp);
	dbms_output.put_line(k_action||':'||sqlerrm);
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
	RAISE;
  WHEN OTHERS THEN
    UTL_HTTP.end_response(l_resp);
	dbms_output.put_line(k_action||':'||sqlerrm);
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
	RAISE;
END strava_http_request;
----------------------------------------------------------------------------------------------------
--bulk load activity streams - activities currently at status 2
----------------------------------------------------------------------------------------------------
PROCEDURE batch_load_activities
(p_quota_pct NUMBER 
,p_quota_abs NUMBER 
) IS
  k_job_name CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.BATCH_LOAD_ACTIVITIES_JOB';
  
  l_counter INTEGER := 0;
  l_next_start TIMESTAMP WITH TIME ZONE := TRUNC(SYSTIMESTAMP,'hh24') + INTERVAL '3' HOUR; 
  l_ts TIMESTAMP WITH TIME ZONE;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>'api_log_usage');

  --DBMS_OUTPUT.PUT_LINE('Background Job ID:'||SYS_CONTEXT('USERENV', 'BG_JOB_ID'));
  api_log_usage;
    
  FOR i IN (
    SELECT activity_id, name, start_date_utc, gear_name, num_pts, manual
    FROM   activities
    WHERE  processing_status < k3_status_stream_loaded
    ORDER BY start_date_utc desc
    FETCH FIRST 90 ROWS ONLY
  ) LOOP
	l_counter := l_counter + 1;
	l_ts := SYSTIMESTAMP AT TIME ZONE 'UTC';
    l_next_start := TRUNC(l_ts, 'HH24') 
                  + NUMTODSINTERVAL(CEIL(EXTRACT(MINUTE FROM l_ts) / 15) * 15, 'MINUTE');

    IF i.manual THEN
	  UPDATE activities
	  SET processing_status = k9_do_not_process
	  WHERE activity_id = i.activity_id;
    ELSIF g_long_read_usage/g_long_read_limit >= p_quota_pct/100 THEN
	  dbms_output.put_line('Long Read Usage Limit: '||g_long_read_usage||'/'||g_long_read_limit||' >= '||p_quota_pct||'%');
	  l_next_start := TRUNC(l_ts) + INTERVAL '1' DAY;
	  EXIT;
    ELSIF g_short_read_usage/g_short_read_limit >= p_quota_pct/100 THEN
	  dbms_output.put_line('Short Read Usage Limit: '||g_short_read_usage||'/'||g_short_read_limit||' >= '||p_quota_pct||'%');
	  EXIT;
	ELSIF l_counter > p_quota_abs THEN
      dbms_output.put_line('Counter Quota Limit: '||l_counter||' > '||p_quota_abs);
	  EXIT;
	ELSIF l_counter > 90 THEN	
      dbms_output.put_line('Counter Absolute Limit: '||l_counter||' > 90');
	  EXIT;
	ELSE
   	  strava_http.get_activity(i.activity_id,TRUE);
	END IF;
  END LOOP;
  
  BEGIN --update job next start
    dbms_scheduler.set_attribute
    (name => k_job_name
    ,attribute => 'START_DATE'
    ,value => l_next_start
    );
    dbms_output.put_line('Job '||k_job_name||' @ '||l_next_start);
  EXCEPTION 
    WHEN OTHERS THEN
	  dbms_output.put_line('Job '||k_job_name||' does not exist');
  END;
  
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END batch_load_activities;
----------------------------------------------------------------------------------------------------
--bulk updated activity descriptions
----------------------------------------------------------------------------------------------------
PROCEDURE batch_update_strava_activity
(p_quota_pct NUMBER 
,p_quota_abs NUMBER 
) IS
  k_job_name CONSTANT VARCHAR2(128 CHAR) := 'STRAVA.UPDATE_STRAVA_ACTIVTY_JOB';
  
  l_counter INTEGER := 0;
  l_next_start TIMESTAMP WITH TIME ZONE := TRUNC(SYSTIMESTAMP,'hh24') + INTERVAL '3' HOUR; 
  l_ts TIMESTAMP WITH TIME ZONE;

  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_job_name);

  api_log_usage;
    
  FOR i IN (
    SELECT activity_id
    FROM   activities
    WHERE  1=1
    --and name = 'Loop'
    --and not description like '%myWindsock%'
	--AND area_list like '%London%'
	AND processing_status = k4_status_areas_processed
    --ORDER BY last_updated desc
    ORDER BY start_date_utc DESC
    --FOR UPDATE OF processing_status
  ) LOOP
    l_counter := l_counter + 1;
    l_ts := SYSTIMESTAMP AT TIME ZONE 'UTC';
    l_next_start := TRUNC(l_ts, 'HH24') 
                  + NUMTODSINTERVAL(CEIL(EXTRACT(MINUTE FROM l_ts) / 15) * 15, 'MINUTE');

    IF g_long_read_usage/g_long_read_limit >= p_quota_pct/100 THEN
      dbms_output.put_line('Long Read Usage Limit: '||g_long_read_usage||'/'||g_long_read_limit||' >= '||p_quota_pct||'%');
      l_next_start := TRUNC(l_ts) + INTERVAL '1' DAY;
      EXIT;
    ELSIF g_short_read_usage/g_short_read_limit >= p_quota_pct/100 THEN
      dbms_output.put_line('Short Read Usage Limit: '||g_short_read_usage||'/'||g_short_read_limit||' >= '||p_quota_pct||'%');
      EXIT;
    ELSIF g_long_all_usage/g_long_all_limit >= p_quota_pct/100 THEN
      dbms_output.put_line('Long All Usage Limit: '||g_long_all_usage||'/'||g_long_all_limit||' >= '||p_quota_pct||'%');
      l_next_start := TRUNC(l_ts) + INTERVAL '1' DAY;
      EXIT;
    ELSIF g_short_all_usage/g_short_all_limit >= p_quota_pct/100 THEN
      dbms_output.put_line('Short All Usage Limit: '||g_short_all_usage||'/'||g_short_all_limit||' >= '||p_quota_pct||'%');
      EXIT;	  
    ELSIF l_counter > p_quota_abs THEN
      dbms_output.put_line('Counter Quota Limit: '||l_counter||' > '||p_quota_abs);
      EXIT;
    ELSIF l_counter > 90 THEN	
      dbms_output.put_line('Counter Absolute Limit: '||l_counter||' > 90');
      EXIT;
    ELSE
      strava_http.update_strava_activity(i.activity_id);
    END IF;
  END LOOP;
  
  BEGIN --update job next start
    dbms_scheduler.set_attribute
    (name => k_job_name
    ,attribute => 'START_DATE'
    ,value => l_next_start
    );
    dbms_output.put_line('Job '||k_job_name||' @ '||l_next_start);
  EXCEPTION 
    WHEN OTHERS THEN
      dbms_output.put_line('Job '||k_job_name||' does not exist');
  END;
  
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END batch_update_strava_activity;
----------------------------------------------------------------------------------------------------
PROCEDURE upsert_activity
(p_activities IN OUT activities%ROWTYPE
,p_force_update BOOLEAN DEFAULT FALSE
) IS
  l_sigmatch BOOLEAN := FALSE;

  k_action CONSTANT VARCHAR2(64 CHAR) := 'upsert_activity';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  --dbms_output.put_line('upserting '||p_activities.activity_id);
  
  l_sigmatch:=strava_sig.activities_signature(p_activities,'S');
  IF p_force_update THEN --force update
    l_sigmatch := FALSE; 
  END IF;

  BEGIN  
    INSERT INTO activities VALUES p_activities;
    dbms_output.put_line(sql%rowcount||' activity inserted');
    COMMIT;

  EXCEPTION 
    WHEN DUP_VAL_ON_INDEX THEN
      IF l_sigmatch THEN
        dbms_output.put_line('Activity not updated');
        ROLLBACK; 
      ELSE
        UPDATE activities
        SET ROW = p_activities
        WHERE  activity_id = p_activities.activity_id;
        dbms_output.put_line(sql%rowcount||' activity updated');   
        COMMIT;
      END IF;
  END;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||'.'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END upsert_activity;
----------------------------------------------------------------------------------------------------
PROCEDURE get_athlete_activities
(p_before    IN TIMESTAMP WITH TIME ZONE 
,p_after     IN TIMESTAMP WITH TIME ZONE 
,p_page      INTEGER 
,p_per_page  INTEGER 
) IS
  l_url      VARCHAR2(4000);
  l_req      UTL_HTTP.req;
  l_resp     UTL_HTTP.resp;
  l_clob     CLOB;
  l_url_sep  VARCHAR2(1 CHAR) := '?';
  
  l_per_page INTEGER;

  j_arr      JSON_ARRAY_T;
  j_obj      JSON_OBJECT_T;
  
  r_activities activities%ROWTYPE;
  l_sigmatch BOOLEAN := FALSE;

  k_action CONSTANT VARCHAR2(64 CHAR) := 'get_athlete_activities';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);

  renew_strava_tokens;
  
  l_url := k_strava_api||'athlete/activities';
  IF p_before IS NOT NULL THEN
    l_url := l_url||l_url_sep||'before='||tstz_to_epoch(p_before);
	l_url_sep := k_ampersand;
  END IF;
  IF p_after IS NOT NULL THEN
    l_url := l_url||l_url_sep||'after='||tstz_to_epoch(p_after);
	l_url_sep := k_ampersand;
  END IF;
  IF p_page > 1 THEN
    l_url := l_url||l_url_sep||'page='||p_page;
	l_url_sep := k_ampersand;
  END IF;

  l_per_page := p_per_page;
  IF l_per_page < 1 THEN l_per_page := 1;
  ELSIF l_per_page > k_max_athlete_activities THEN l_per_page := k_max_athlete_activities;
  END IF;
  IF p_per_page >= 1 THEN
    l_url := l_url||l_url_sep||'per_page='||l_per_page;
  END IF;
  l_clob := strava_http_request(l_url);

  --pretty_json(l_clob);

  --Parse JSON array
  j_arr := JSON_ARRAY_T.parse(l_clob);

  FOR i IN 0 .. j_arr.get_size - 1 
   LOOP
    j_obj        := TREAT(j_arr.get(i) AS JSON_OBJECT_T);

    r_activities.activity_id      := j_obj.get_number('id');
  
    BEGIN
      SELECT * INTO r_activities FROM activities WHERE activity_id = r_activities.activity_id FOR UPDATE;
    EXCEPTION
      WHEN no_data_found THEN 
	    dbms_output.put_line(k_action||': Activity '||r_activities.activity_id||' not found');
	    NULL;
    END;

    r_activities.athlete_id        := j_obj.get_object('athlete').get_number('id');
    r_activities.start_date_utc    := iso8601_utc(j_obj.get_string('start_date'));
    r_activities.start_date_local  := iso8601_tz(j_obj.get_string('start_date_local'), j_obj.get_string('timezone'));
    r_activities.timezone          := j_obj.get_string('timezone');
    r_activities.utc_offset        := j_obj.get_number('utc_offset');
    r_activities.name              := j_obj.get_string('name');
    r_activities.type              := j_obj.get_string('type');
    r_activities.device_name       := j_obj.get_string('device_name'); 
    r_activities.elapsed_time      := j_obj.get_number('elapsed_time');
    r_activities.distance_km       := j_obj.get_number('distance')/1000;

    r_activities.gear_id           := j_obj.get_string('gear_id');

    r_activities.moving_time       := j_obj.get_number('moving_time');
    r_activities.max_speed         := j_obj.get_number('max_speed');
    r_activities.average_speed     := j_obj.get_number('average_speed');
    r_activities.elevation_gain    := j_obj.get_number('total_elevation_gain');
    r_activities.elevation_high    := j_obj.get_number('elev_high');
    r_activities.elevation_low     := j_obj.get_number('elev_low');
    r_activities.average_watts     := j_obj.get_number('average_watts');
    r_activities.kilojoules        := j_obj.get_number('kilojoules');
    r_activities.trainer           := TO_BOOLEAN(j_obj.get_string('trainer'));
    r_activities.commute           := TO_BOOLEAN(j_obj.get_string('commute'));
    r_activities.manual            := TO_BOOLEAN(j_obj.get_string('manual'));
    r_activities.private           := TO_BOOLEAN(j_obj.get_string('private'));
    r_activities.visibility        := j_obj.get_string('visibility');
    r_activities.flagged           := TO_BOOLEAN(j_obj.get_string('flagged'));
    r_activities.photo_count       := j_obj.get_number('total_photo_count');
----------------------------------------------------------------------------------------------------  
--only decode polyline if status <= 1
----------------------------------------------------------------------------------------------------  
----------------------------------------------------------------------------------------------------  
    l_sigmatch := strava_sig.activities_signature(r_activities,'C'); --check signature
    IF l_sigmatch THEN
      NULL; --nothing has changed
    ELSE
      r_activities.map_polyline     := j_obj.get_object('map').get_string('summary_polyline');
      r_activities.GEOM             := strava_sdo.polyline_to_geom(r_activities.map_polyline);
      --dbms_output.put_line('XXX6-');
      r_activities.GPX              := strava_sdo.geom_to_gpx(r_activities.GEOM,r_activities.name);
      --dbms_output.put_line('XXX7-'||DBMS_LOB.GETLENGTH(r_activities.GPX.getClobVal()));
      r_activities.num_pts          := SDO_UTIL.GETNUMVERTICES(r_activities.geom);
      --dbms_output.put_line('XXX8-'||r_activities.num_pts||' points');
      r_activities.mbr              := sdo_geom.sdo_mbr(r_activities.geom);
      --dbms_output.put_line('XXX9');
      r_activities.processing_status := k1_status_athlete_loaded;
    END IF;
----------------------------------------------------------------------------------------------------  
    dbms_output.put_line(r_activities.activity_id
	              ||':'||r_activities.type
	              ||':'||r_activities.name
	              ||':'||TO_CHAR(r_activities.start_date_utc,k_iso8601_tzr)
	              ||':'||r_activities.distance_km||'km'
   	              ||':'||NVL(LENGTH(r_activities.description),0)||' chars'
				  );

    upsert_activity(r_activities);

    IF r_activities.processing_status <= k3_status_stream_loaded THEN
	  strava_job.create_get_activity_job(r_activities.activity_id);
    END IF;

  END LOOP;
--COMMIT;
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
	RAISE;
END get_athlete_activities;
----------------------------------------------------------------------------------------------------
-- basic update of rowtype from json
----------------------------------------------------------------------------------------------------
PROCEDURE update_activity_with_json
(p_activities  IN OUT activities%ROWTYPE
,p_jobj        JSON_OBJECT_T
) IS
  j_subobj   JSON_OBJECT_T;  

  k_action CONSTANT VARCHAR2(64 CHAR) := 'update_activity_with_json';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);

  p_activities.activity_id      := p_jobj.get_number('id');
  --dbms_output.put_line('Activity ID:'||p_activity_id||':'||p_activities.activity_id);
  
  p_activities.athlete_id        := p_jobj.get_object('athlete').get_number('id');
  p_activities.start_date_utc    := iso8601_utc(p_jobj.get_string('start_date'));
  p_activities.start_date_local  := iso8601_tz(p_jobj.get_string('start_date_local'), p_jobj.get_string('timezone'));
  p_activities.timezone          := p_jobj.get_string('timezone');
  p_activities.utc_offset        := p_jobj.get_number('utc_offset');
  p_activities.name              := p_jobj.get_string('name');
  p_activities.type              := p_jobj.get_string('type');
  p_activities.device_name       := p_jobj.get_string('device_name'); 
  
  ----------------------------------------------------------------------------------------------------
  --p_activities.description       := normalize_to_utf8(p_jobj.get_string('description'));
  p_activities.description       := p_jobj.get_clob('description');
  ----------------------------------------------------------------------------------------------------

  p_activities.elapsed_time      := p_jobj.get_number('elapsed_time');
  p_activities.distance_km       := p_jobj.get_number('distance')/1000;
  ---dbms_output.put_line('XXX1');
  p_activities.gear_id           := p_jobj.get_string('gear_id');
  --p_activities.gear_id           := p_jobj.get_object('gear').get_string('id');

  --no gear on some activitiess e.g. NordicSkii
  --see https://support.strava.com/hc/en-us/articles/216918727-Adding-Gear-to-Your-Activities-on-Strava#:~:text=Shoes%20can%20be%20assigned%20to,which%20sport%20type%20(s).
  --Bikes can be assigned to Ride, Mountain Bike Ride, Gravel Ride, E-Bike Ride, E-Mountain Bike Ride, Handcycle, Virtual Rides, or Velomobile Rides
  --Shoes can be assigned to Run, Trail Run, Walk, Virtual Runs, or Hike activities. 
  IF p_activities.type IN('Ride','Walk','Hike','VirtualRide' --known to have gear
                         ,'MountainBikeRide','GravelRide','E-BikeRide','E-MountainBikeRide','Handcycle','VelomobileRide' --documented to have gear
                         ,'Run','TrailRun','VirtualRun') THEN
    j_subobj                    := p_jobj.get_object('gear');
	IF j_subobj IS NOT NULL THEN
      p_activities.gear_name      := j_subobj.get_string('name');
	END IF;
  END IF;
  --dbms_output.put_line('XXX2');

  p_activities.moving_time      := p_jobj.get_number('moving_time');
  p_activities.max_speed        := p_jobj.get_number('max_speed');
  p_activities.average_speed    := p_jobj.get_number('average_speed');
  p_activities.elevation_gain   := p_jobj.get_number('total_elevation_gain');
  p_activities.elevation_high   := p_jobj.get_number('elev_high');
  p_activities.elevation_low    := p_jobj.get_number('elev_low');
  p_activities.average_watts    := p_jobj.get_number('average_watts');
  p_activities.calories         := p_jobj.get_number('calories');
  p_activities.kilojoules       := p_jobj.get_number('kilojoules');
  p_activities.trainer          := TO_BOOLEAN(p_jobj.get_string('trainer'));
  p_activities.commute          := TO_BOOLEAN(p_jobj.get_string('commute'));
  p_activities.manual           := TO_BOOLEAN(p_jobj.get_string('manual'));
  p_activities.private          := TO_BOOLEAN(p_jobj.get_string('private'));
  p_activities.visibility       := p_jobj.get_string('visibility');
  p_activities.flagged          := TO_BOOLEAN(p_jobj.get_string('flagged'));

  --dbms_output.put_line('XXX3');
  p_activities.photo_count    := p_jobj.get_object('photos').get_number('count');
  --dbms_output.put_line('XXX4');

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END update_activity_with_json;
----------------------------------------------------------------------------------------------------
-- get activity details from strava via API
----------------------------------------------------------------------------------------------------
PROCEDURE get_activity
(p_activity_id         activities.activity_id%TYPE
,p_get_stream          IN BOOLEAN 
,p_include_all_efforts IN BOOLEAN 
) IS
  l_url      VARCHAR2(4000);
  l_url_sep  VARCHAR2(1 CHAR) := '?';
  l_clob     CLOB;
  l_sigmatch BOOLEAN;
  l_force_update BOOLEAN := FALSE;

  j_obj      JSON_OBJECT_T;  
  r_activities activities%ROWTYPE;

  k_action CONSTANT VARCHAR2(64 CHAR) := 'get_activity';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
  
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  
  BEGIN
    SELECT * 
	INTO   r_activities 
	FROM   activities 
	WHERE  activity_id = p_activity_id 
	FOR UPDATE;
  EXCEPTION
    WHEN no_data_found THEN 
	  r_activities.activity_id := p_activity_id;
	  dbms_output.put_line(k_action||': Activity '||r_activities.activity_id||' not found');
	  NULL;
  END;

  renew_strava_tokens;
  l_url := k_strava_api||'activities/'||p_activity_id;
  IF p_include_all_efforts IS NOT NULL THEN
    l_url := l_url||l_url_sep||'include_all_efforts='||booltochar(p_include_all_efforts);
  END IF;
  l_clob := strava_http_request(l_url); 
  --print_clob(l_clob);
  --pretty_json(l_clob);
  --Parse JSON array

  j_obj := JSON_OBJECT_T.parse(l_clob);
  update_activity_with_json(r_activities, j_obj);
  
----------------------------------------------------------------------------------------------------  
  l_sigmatch := strava_sig.activities_signature(r_activities,'C'); --check signature
  IF NOT l_sigmatch OR (p_get_stream AND r_activities.processing_status <= k2_status_activity_loaded) THEN
    r_activities.map_polyline     := j_obj.get_object('map').get_clob('polyline');
	IF r_activities.manual THEN
	  r_activities.GEOM := NULL;
	  r_activities.GPX := NULL;
	  r_activities.processing_status := k9_do_not_process;
    ELSIF p_get_stream THEN
	  l_force_update := TRUE;
      get_activity_stream(r_activities); --and this also sets status=3
    ELSIF NOT p_get_stream THEN
      --dbms_output.put_line('XXX5');
      r_activities.GEOM              := strava_sdo.polyline_to_geom(r_activities.map_polyline);
      --dbms_output.put_line('XXX6-');
      r_activities.GPX               := strava_sdo.geom_to_gpx(r_activities.GEOM,r_activities.name);
      --dbms_output.put_line('XXX7-'||DBMS_LOB.GETLENGTH(r_activities.GPX.getClobVal()));
      r_activities.processing_status := k2_status_activity_loaded;
    END IF;
    r_activities.num_pts          := SDO_UTIL.GETNUMVERTICES(r_activities.geom);
    --dbms_output.put_line('XXX8-'||r_activities.num_pts||' points');
    r_activities.mbr              := sdo_geom.sdo_mbr(r_activities.geom);
    --dbms_output.put_line('XXX9');
  END IF;
----------------------------------------------------------------------------------------------------  
  dbms_output.put_line(r_activities.activity_id
	            ||':'||r_activities.type
	            ||':'||r_activities.name
	            ||':'||TO_CHAR(r_activities.start_date_utc,k_iso8601_tzr)
	            ||':'||r_activities.distance_km||'km'
 	        	||':'||NVL(LENGTH(r_activities.description),0)||' chars'
				);

  upsert_activity(r_activities, p_force_update=>l_force_update);
  IF r_activities.processing_status = k3_status_stream_loaded THEN
    strava_job.create_activity_hsearch_upd_job(r_activities.activity_id);
  END IF;
  COMMIT;
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION
  WHEN e_json_null_self THEN
    pretty_json(l_clob);
    dbms_output.put_line(k_action||'('||p_activity_id||',p_get_stream='||booltochar(p_get_stream)||'):'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
	RAISE;
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||'('||p_activity_id||',p_get_stream='||booltochar(p_get_stream)||'):'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
	RAISE;
END get_activity;
----------------------------------------------------------------------------------------------------
PROCEDURE get_activity_gpx
(p_activity_id         activities.activity_id%TYPE
) IS
  l_url    VARCHAR2(4000);
  l_clob   CLOB;
  
  k_action CONSTANT VARCHAR2(64 CHAR) := 'get_activity_gpx';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);

  renew_strava_tokens;
  l_url := k_strava_api||'activities/'||p_activity_id||'/export_gpx';
  l_clob := strava_http_request(l_url); 
  
  --print_clob(l_clob);

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END get_activity_gpx;
----------------------------------------------------------------------------------------------------
PROCEDURE get_activity_stream_id
(p_activity_id activities.activity_id%TYPE
) IS
  r_activities activities%ROWTYPE;

  k_action CONSTANT VARCHAR2(64 CHAR) := 'get_activity_stream_id';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  
  SELECT * INTO r_activities 
  FROM activities 
  WHERE activity_id = p_activity_id 
  FOR UPDATE;  

  get_activity_stream(r_activities);
  
  --print_clob(r_activities.gpx.getClobVal());
  --print_clob(SDO_UTIL.TO_WKTGEOMETRY(r_activities.geom));

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN OTHERS THEN 
    dbms_output.put_line(k_action||':'||sqlerrm);  
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END get_activity_stream_id;
----------------------------------------------------------------------------------------------------
PROCEDURE get_activity_stream
(p_activities IN OUT activities%ROWTYPE
) IS
  l_url        VARCHAR2(4000);
  l_clob       CLOB;
  l_gpx_clob   CLOB;

  -- JSON objects
  j_obj           JSON_OBJECT_T;
  j_latlng_arr    JSON_ARRAY_T;
  j_altitude_arr  JSON_ARRAY_T;
  j_time_arr      JSON_ARRAY_T;
  j_heartrate_arr JSON_ARRAY_T := NULL;
  j_cadence_arr   JSON_ARRAY_T := NULL;
  j_power_arr     JSON_ARRAY_T := NULL;
  j_point_arr     JSON_ARRAY_T;

  -- Loop variables
  l_counter INTEGER := 0;
  i INTEGER;
  l_point_lat NUMBER;
  l_point_lng NUMBER;
  l_point_alt NUMBER;
  l_point_sec NUMBER;
  l_hr NUMBER;
  l_cad NUMBER;
  l_pwr NUMBER;

  -- Start date for timestamps
  l_start_date TIMESTAMP;

  -- Flags for optional streams
  l_has_hr BOOLEAN := FALSE;
  l_has_cad BOOLEAN := FALSE;
  l_has_pwr BOOLEAN := FALSE;

  -- variables for building geometry object
  l_coords       SDO_ORDINATE_ARRAY := SDO_ORDINATE_ARRAY();
  l_geom         SDO_GEOMETRY;
  
  k_action CONSTANT VARCHAR2(64 CHAR) := 'get_activity_stream';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
			   
  renew_strava_tokens;
  l_url := k_strava_api||'activities/'||p_activities.activity_id
                       ||'/streams?keys=latlng,altitude,time,heartrate,cadence,power'||k_ampersand||'key_by_type=true';
  l_clob := strava_http_request(l_url); 
  
  j_obj := JSON_OBJECT_T.parse(l_clob);
  --pretty_json(l_clob);
  DBMS_LOB.freetemporary(l_clob); --finished with it now
  
  l_start_date := p_activities.start_date_utc;
  -- Required streams
  j_latlng_arr   := JSON_ARRAY_T(j_obj.get_object('latlng').get('data'));
  j_time_arr     := JSON_ARRAY_T(j_obj.get_object('time').get('data'));
  j_altitude_arr := JSON_ARRAY_T(j_obj.get_object('altitude').get('data'));
  -- Optional streams
  IF j_obj.has('heartrate') THEN
    j_heartrate_arr := JSON_ARRAY_T(j_obj.get_object('heartrate').get('data'));
    l_has_hr := TRUE;
  END IF;
  IF j_obj.has('cadence') THEN
    j_cadence_arr := JSON_ARRAY_T(j_obj.get_object('cadence').get('data'));
    l_has_cad := TRUE;
  END IF;
  IF j_obj.has('power') THEN
    j_power_arr := JSON_ARRAY_T(j_obj.get_object('power').get('data'));
    l_has_pwr := TRUE;
  END IF;

  --------------------------
  -- Build GPX CLOB with namespaces
  --------------------------
  DBMS_LOB.createtemporary(l_gpx_clob, TRUE);

  -- GPX header with namespaces
  DBMS_LOB.append(l_gpx_clob, '<?xml version="1.0" encoding="UTF-8"?>' || k_lf 
    ||'<gpx version="1.1" creator="'||k_creator||'" ' 
    ||'xmlns="http://www.topografix.com/GPX/1/1" ' 
    ||'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' 
    ||'xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1" ' 
    ||'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 ' 
    ||'http://www.topografix.com/GPX/1/1/gpx.xsd ' 
    ||'http://www.garmin.com/xmlschemas/TrackPointExtension/v1 ' 
    ||'http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd">' || k_lf
	);

  --replace & with &amp or you get an xml parse error
  DBMS_LOB.append(l_gpx_clob, 
    '<trk><name>'||REPLACE(p_activities.name, k_ampersand, k_ampersand||'amp;')||' ('|| p_activities.activity_id || ')</name><trkseg>' || k_lf);

  -- Loop through points
  FOR i IN 1 .. j_latlng_arr.get_size LOOP
    j_point_arr := JSON_ARRAY_T(j_latlng_arr.get(i-1)); -- each inner array [lat, lng]
    l_point_lat := j_point_arr.get_Number(0);
    l_point_lng := j_point_arr.get_Number(1);
    l_point_alt := j_altitude_arr.get_Number(i-1);
    l_point_sec := j_time_arr.get_Number(i-1);
    --dbms_output.put_line('Point-'||l_point_lat||','||l_point_lng||','||l_point_alt||','||l_point_sec);

    -- Convert lat/lng pairs into SDO coordinates
    l_coords.EXTEND(2);
    l_counter := l_counter + 1;
    l_coords(l_counter) := l_point_lng; -- longitude
    l_counter := l_counter + 1;
    l_coords(l_counter) := l_point_lat;

    -- Optional data for GPX
    l_hr := NULL; l_cad := NULL; l_pwr := NULL;
    IF l_has_hr  THEN 
	  l_hr  := j_heartrate_arr.get_Number(i-1); 
    END IF;
    IF l_has_cad THEN 
	  l_cad := j_cadence_arr.get_Number(i-1);    
	END IF;
    IF l_has_pwr THEN 
	  l_pwr := j_power_arr.get_Number(i-1); 
	END IF;

    -- Write point with pretty indentation and extensions
    DBMS_LOB.append(l_gpx_clob,
        '<trkpt lat="' || l_point_lat || '" lon="' || l_point_lng || '">' || k_lf ||
        '  <ele>' || l_point_alt || '</ele>' || k_lf ||
        '  <time>' || TO_CHAR(l_start_date + NUMTODSINTERVAL(l_point_sec,'SECOND'),k_iso8601) || '</time>' || k_lf ||
        CASE
          WHEN l_has_hr OR l_has_cad OR l_has_pwr THEN
            '  <extensions>' || k_lf ||
            (CASE WHEN l_has_hr  THEN '   <gpxtpx:TrackPointExtension><gpxtpx:hr>'     || l_hr || '</gpxtpx:hr></gpxtpx:TrackPointExtension>' || k_lf ELSE '' END) ||
            (CASE WHEN l_has_cad THEN '   <gpxtpx:TrackPointExtension><gpxtpx:cad>'   || l_cad || '</gpxtpx:cad></gpxtpx:TrackPointExtension>' || k_lf ELSE '' END) ||
            (CASE WHEN l_has_pwr THEN '   <gpxtpx:TrackPointExtension><gpxtpx:power>' || l_pwr || '</gpxtpx:power></gpxtpx:TrackPointExtension>' || k_lf ELSE '' END) ||
            '  </extensions>' || k_lf
          ELSE ''
        END ||
        '</trkpt>' || k_lf
        );
  END LOOP;

  -- GPX footer
  DBMS_LOB.append(l_gpx_clob, '</trkseg></trk>'||k_lf||'</gpx>');
  p_activities.gpx := XMLTYPE(l_gpx_clob);
  --print_clob(l_gpx_clob);

  -- Build SDO_GEOMETRY object (LineString)
  p_activities.geom := SDO_GEOMETRY(
        k_geom_line, -- 2D line
        k_wgs84,
        NULL,
        SDO_ELEM_INFO_ARRAY(1, 2, 1),
        l_coords
  );
  p_activities.processing_status := k3_status_stream_loaded;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN e_xml_parse_fail THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    print_clob(l_gpx_clob);
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END get_activity_stream;
----------------------------------------------------------------------------------------------------
PROCEDURE get_gear
(p_gear_id  IN VARCHAR2
) IS
  l_url      VARCHAR2(4000);
  l_clob     CLOB;

  j_obj      JSON_OBJECT_T;
  l_id       VARCHAR2(20 CHAR);
  
  r_gear     gear%ROWTYPE;

  k_action CONSTANT VARCHAR2(64 CHAR) := 'get_gear';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  
  BEGIN
    SELECT * INTO r_gear FROM gear WHERE gear_id = p_gear_id FOR UPDATE;
  EXCEPTION
    WHEN no_data_found THEN null;
  END;
  
  renew_strava_tokens;
  l_url := k_strava_api||'gear/'||p_gear_id;
  l_clob := strava_http_request(l_url);

  pretty_json(l_clob);
  --Parse JSON array
  j_obj := JSON_OBJECT_T.parse(l_clob);
  l_id  := j_obj.get_string('id');

  IF r_gear.gear_id = p_gear_id THEN
    --dbms_output.put_line('Update');
    UPDATE gear_dv d
    SET    d.data = JSON_TRANSFORM
           (value
           ,RENAME '$.id' = '_id'
           ,REMOVE '$.frame_type'
           ,REMOVE '$.notification_distance'
           )
    FROM JSON_TABLE(
           l_clob,
           '$[*]'
           COLUMNS (
             value CLOB FORMAT JSON PATH '$'
           ))
    WHERE d.data."_id" = l_id;
  ELSE
    --dbms_output.put_line('Insert');
    INSERT INTO gear_dv
    SELECT JSON_TRANSFORM
           (value
           ,RENAME '$.id' = '_id'
           ,REMOVE '$.frame_type'
           ,REMOVE '$.notification_distance'
           )
    FROM JSON_TABLE(
           l_clob,
           '$[*]'
           COLUMNS (
             value CLOB FORMAT JSON PATH '$'
           )
     );
  END IF;
  COMMIT; 
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);

EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
END get_gear;
----------------------------------------------------------------------------------------------------
PROCEDURE purge_api_log
IS
  k_action CONSTANT VARCHAR2(64 CHAR) := 'purge_api_log';  
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);  
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  
  DELETE FROM api_log
  WHERE request_time < trunc(SYSTIMESTAMP AT TIME ZONE 'UTC')
  AND   request_time < SYSTIMESTAMP AT TIME ZONE 'UTC' - INTERVAL '15' MINUTE;

  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END purge_api_log;
----------------------------------------------------------------------------------------------------
PROCEDURE renew_strava_tokens (p_force BOOLEAN) IS
  l_job_name CONSTANT VARCHAR2(128) := 'STRAVA.RENEW_STRAVA_TOKENS_JOB';
  l_renew      BOOLEAN := FALSE;
  
  l_url        VARCHAR2(4000);
  l_req        UTL_HTTP.req;
  l_resp       UTL_HTTP.resp;
  l_clob       CLOB;

  l_json       JSON_ARRAY_T;
  j_obj        JSON_OBJECT_T;  

  k_action CONSTANT VARCHAR2(64 CHAR) := 'renew_strava_token';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  EXECUTE IMMEDIATE 'ALTER SESSION SET TIME_ZONE = ''UTC''';

  -- Load token info
  SELECT   client_id,   client_secret,   access_token,   refresh_token,   expires_at
    INTO g_client_id, g_client_secret, g_access_token, g_refresh_token, g_expires_at
    FROM strava_tokens
   WHERE ROWNUM = 1;

  -- Refresh token if expired
  IF p_force THEN 
    l_renew := TRUE;
  ELSIF g_expires_at <= SYSTIMESTAMP THEN
    l_renew := TRUE;
  ELSIF g_expires_at IS NULL THEN
    l_renew := TRUE;
  END IF;
  IF l_renew THEN
    l_url := k_strava_url||'oauth/token' ||
             '?client_id=' || g_client_id ||
             k_ampersand||'client_secret=' || g_client_secret ||
             k_ampersand||'grant_type=refresh_token' ||
             k_ampersand||'refresh_token=' || g_refresh_token;

    l_req := UTL_HTTP.begin_request(l_url, 'POST', 'HTTP/1.1');
    l_resp := UTL_HTTP.get_response(l_req);

    DBMS_LOB.createtemporary(l_clob, TRUE);
    LOOP
      DECLARE 
        l_buf VARCHAR2(32767);
      BEGIN
        UTL_HTTP.read_text(l_resp, l_buf, 32767);
        --l_clob := l_clob || l_buf;
  	    DBMS_LOB.writeappend(l_clob, LENGTH(l_buf), l_buf);
      EXCEPTION 
        WHEN UTL_HTTP.end_of_body THEN EXIT; 
      END;
    END LOOP;
    UTL_HTTP.end_response(l_resp);

    --dbms_output.put_line(l_clob);
    j_obj := JSON_OBJECT_T.parse(l_clob);
    
    g_access_token  := j_obj.get_string('access_token');
    g_refresh_token := j_obj.get_string('refresh_token');

    g_expires_at := SYSDATE + NUMTODSINTERVAL(j_obj.get_number('expires_in'), 'SECOND');
    
    dbms_scheduler.set_attribute 
    (name => l_job_name
    ,attribute=>'START_DATE'
    ,value=> g_expires_at
    );
    
    -- Update token table
    UPDATE strava_tokens
       SET access_token = g_access_token,
           refresh_token = g_refresh_token,
           expires_at = g_expires_at
    WHERE  client_id = g_client_id;
    COMMIT;
  END IF;
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION 
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END renew_strava_tokens;
----------------------------------------------------------------------------------------------------
-- update description on a single strava activity
----------------------------------------------------------------------------------------------------
PROCEDURE update_strava_activity
(p_activity_id IN activities.activity_id%TYPE
) IS
  l_url         VARCHAR2(4000);
  l_clob        CLOB;
  l_counter     INTEGER := 0;

  j_obj         JSON_OBJECT_T;
  r_activities activities%ROWTYPE;

  k_action CONSTANT VARCHAR2(64 CHAR) := 'update_strava_activity';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  
  r_activities.activity_id := p_activity_id;
  
  SELECT *
  INTO   r_activities
  FROM   activities
  WHERE  processing_status = k4_status_areas_processed
  AND    activity_id = p_activity_id
  FOR UPDATE OF processing_status;

  renew_strava_tokens;
  l_url := k_strava_api||'activities/'||p_activity_id;
  l_clob := strava_http_request(l_url); 
  --pretty_json(l_clob); 
  --Parse JSON array
  j_obj := JSON_OBJECT_T.parse(l_clob);
  --simple update of rowtype from json
  update_activity_with_json(r_activities, j_obj);
  
  --clean string after incorrect character set conversion
  r_activities.description := clean_string(r_activities.description);

  LOOP
    l_counter := l_counter + 1;
    --update the PlaceCloud in description 
    strava_sdo.update_activity_description(r_activities);
  
    l_clob := strava_http_request(l_url,'PUT','description='||r_activities.description); 
    --pretty_json(l_clob);
    --print_clob(l_clob);
    --Parse JSON array
    j_obj := JSON_OBJECT_T.parse(l_clob);

    --l_description := normalize_to_utf8(j_obj.get_string('description'));
    --l_description := j_obj.get_string('description');

    IF r_activities.description = j_obj.get_string('description') THEN
	  --r_activities.processing_status := k6_status_description_updated;
      dbms_output.put_line('Updated description for activity '||p_activity_id||' matches');
	  EXIT;
    ELSE
	  --sssr_activities.processing_status := k5_status_area_list_updated;
      dbms_output.put_line('Warning: Updated description for activity '||p_activity_id||' does not matchf');
	  EXIT WHEN l_counter >= 1;
	  r_activities.description := clean_string(j_obj.get_string('description'));
    END IF;
  END LOOP;
  
  UPDATE activities
  SET ROW = r_activities
  --SET    description = r_activities.description
  --,      processing_status = k6_status_description_updated
  WHERE  activity_id = p_activity_id
  AND    processing_status = k4_status_areas_processed
  ;

  COMMIT;
  
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||'('||p_activity_id||'):'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END update_strava_activity;
----------------------------------------------------------------------------------------------------
PROCEDURE create_webhook
(p_callback_url CLOB
) IS
  l_url      VARCHAR2(4000);
  l_clob     CLOB;

  j_obj      JSON_OBJECT_T;

  g_verify_token CONSTANT VARCHAR2(100) := 'PlaceCloud42'; 

  k_action CONSTANT VARCHAR2(64 CHAR) := 'create_webhook';
  l_module VARCHAR2(64 CHAR);
  l_action VARCHAR2(64 CHAR);
BEGIN
  dbms_application_info.read_module(module_name=>l_module,action_name=>l_action);
  dbms_application_info.set_module(module_name=>k_module,action_name=>k_action);
  
  renew_strava_tokens;
  l_url := k_strava_api||'push_subscriptions?'
               ||'client_id='||g_client_id
  ||k_ampersand||'client_secret='||g_client_secret
  ||k_ampersand||'callback_url='||p_callback_url
  ||k_ampersand||'verify_token='||g_verify_token;
  
  l_clob := strava_http_request(l_url,'POST');
  
  pretty_json(l_clob);
  --print_clob(l_clob);
  --Parse JSON array
  dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line(k_action||':'||sqlerrm);
    ROLLBACK;
    dbms_application_info.set_module(module_name=>l_module,action_name=>l_action);
    RAISE;
END create_webhook;
----------------------------------------------------------------------------------------------------
END strava_http;
/
--show errors
spool off
