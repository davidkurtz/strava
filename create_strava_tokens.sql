REM create_strava_tokens.sql
REM see https://www.strava.com/settings/api
clear screen
set echo on serveroutput on
spool create_strava_tokens.lst
ALTER SESSION SET current_schema = STRAVA;

--DROP TABLE strava.strava_tokens;
CREATE TABLE strava.strava_tokens (
  client_id     VARCHAR2(100),
  client_secret VARCHAR2(100),
  access_token  VARCHAR2(4000),
  refresh_token VARCHAR2(4000),
  expires_at    TIMESTAMP
);

ALTER TABLE strava.strava_tokens 
add constraint strava_tokens_pk primary key (client_id)
/
ALTER TABLE strava.strava_tokens MODIFY (client_id NOT NULL)
/
ALTER TABLE strava.strava_tokens MODIFY (client_secret NOT NULL)
/
ALTER TABLE strava.strava_tokens MODIFY (access_token NOT NULL)
/

desc strava_tokens

delete from strava.strava_tokens;
Insert into strava.strava_tokens 
(client_id, client_secret, access_token, refresh_token, expires_at)
values 
('123456'
,'1234567890123456789012345678901234567890'
,'1234567890123456789012345678901234567890'
,'1234567890123456789012345678901234567890'
,TO_DATE('2026-02-06T16:18:49Z','YYYY-MM-DD"T"HH24:MI:SS"Z"'))
/
commit;

DECLARE
  l_url       VARCHAR2(4000);
  l_req       UTL_HTTP.req;
  l_resp      UTL_HTTP.resp;
  l_clob      CLOB;
  l_token     VARCHAR2(4000);

  l_json   JSON_OBJECT_T;
  l_name   VARCHAR2(100);
BEGIN
  -- Get token from table
  SELECT access_token INTO l_token FROM strava_tokens WHERE ROWNUM = 1;

  l_url := 'https://www.strava.com/api/v3/athlete';
  
  -- Start HTTP request
  l_req := UTL_HTTP.begin_request(l_url, 'GET', 'HTTP/1.1');

  -- Add Authorization header
  UTL_HTTP.set_header(l_req, 'Authorization', 'Bearer ' || l_token);

  -- Get response
  l_resp := UTL_HTTP.get_response(l_req);

  -- Read CLOB
  DBMS_LOB.createtemporary(l_clob, TRUE);
  LOOP
    DECLARE
      l_buffer VARCHAR2(32767);
    BEGIN
      UTL_HTTP.read_text(l_resp, l_buffer, 32767);
      l_clob := l_clob || l_buffer;
    EXCEPTION
      WHEN UTL_HTTP.end_of_body THEN
        EXIT;
    END;
  END LOOP;

  UTL_HTTP.end_response(l_resp);

  -- Print JSON response
  DBMS_OUTPUT.put_line(l_clob);
  l_json := JSON_OBJECT_T.parse(l_clob); -- replace with l_clob
  l_name := l_json.get_string('firstname') || ' ' || l_json.get_string('lastname');
  DBMS_OUTPUT.put_line('Athlete: ' || l_name);

END;
/
spool off
