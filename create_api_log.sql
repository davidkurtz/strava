REM create_api_log.sql
clear screen
set echo on
spool create_api_log.lst

CREATE TABLE api_log
(request_time TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
,req_type     VARCHAR2(4 CHAR)
,url          VARCHAR2(1000 CHAR)
,http_status  NUMBER
,short_usage  NUMBER
,long_usage   NUMBER
);

ALTER TABLE api_log ADD req_type VARCHAR2(4);
ALTER TABLE api_log MODIFY url VARCHAR2(1000 CHAR);
ALTER TABLE api_log RENAME COLUMN short_usage TO short_read_usage;
ALTER TABLE api_log RENAME COLUMN long_usage TO long_read_usage;
ALTER TABLE api_log ADD short_all_usage number;
ALTER TABLE api_log ADD long_all_usage number;

desc api_log

CREATE INDEX api_log ON api_log(request_time);

--create a purge job at 00:15

SELECT COUNT(*)
FROM api_log
WHERE request_time > SYSTIMESTAMP - INTERVAL '15' MINUTE;

select * from api_log
--WHERE request_time > SYSTIMESTAMP - INTERVAL '15' MINUTE;
order by request_time desc
/
spool off
