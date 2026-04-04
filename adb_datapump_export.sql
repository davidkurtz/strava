REM adb_datapump_export.sql
clear screen
set echo on serveroutput on 

----------------------------------------------------------------------------------------------------
-- OCI BUcket : https://cloud.oracle.com/object-storage/buckets/lrp1qmpxv8ea/bucket-gofaster1/details?region=uk-london-1
-- do the export
----------------------------------------------------------------------------------------------------
clear screen
set serveroutput on echo on 
DECLARE
  h NUMBER;
  l_file_name VARCHAR2(100);
  l_dir VARCHAR2(100) := 'DATA_PUMP_DIR';
BEGIN
  l_file_name := 'export_strava_'||TO_CHAR(SYSDATE,'YYYYMMDD');
  h := DBMS_DATAPUMP.OPEN
       (operation => 'EXPORT'
       --,job_mode => 'FULL'
       ,job_mode => 'SCHEMA'
       );

  dbms_datapump.set_parameter
       (handle => h
       ,name   => 'COMPRESSION'
       ,value  => 'ALL'
	   );
  dbms_datapump.set_parameter
       (handle => h
       ,name   => 'ESTIMATE'
       ,value  => 'BLOCKS'
	   );
  dbms_datapump.set_parameter
       (handle => h
       ,name   => 'CHECKSUM'
       ,value  => 1
	   );

  DBMS_DATAPUMP.ADD_FILE
       (handle    => h
       ,filename  => l_file_name||'_%U.dmp'
       ,directory => l_dir
       ,filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_DUMP_FILE
       ,reusefile => 1
       );
	   
  DBMS_DATAPUMP.ADD_FILE
       (handle    => h
	   ,filename  => l_file_name||'.log'
       ,directory => l_dir
       ,filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_LOG_FILE
       ,reusefile => 1
  );

  DBMS_DATAPUMP.METADATA_FILTER(h, 'SCHEMA_EXPR', 'IN (''STRAVA'')');
  DBMS_DATAPUMP.START_JOB(h);  
END;
/

----------------------------------------------------------------------------------------------------
--see what is running
----------------------------------------------------------------------------------------------------
column owner_name format a10
column job_name format a20
column operation format a10
column job_mode format a10
column state format a12
select * from dba_datapump_jobs
/


/*
OWNER_NAME JOB_NAME             OPERATION JOB_MODE STATE        DEGREE ATTACHED_SESSIONS DATAPUMP_SESSIONS
---------- -------------------- --------- -------- ------------ ------ ----------------- -----------------
ADMIN     SYS_EXPORT_SCHEMA_01  EXPORT    SCHEMA   EXECUTING         1                 1                 3
ADMIN     SYS_EXPORT_FULL_01    EXPORT    FULL     NOT RUNNING       0                 0                 0
*/                                                                

select *
from dba_datapump_sessions p
  left outer join gv$session s on s.inst_id = p.inst_id and s.saddr = p.saddr
;

/*
OWNER_NAME JOB_NAME                INST_ID SADDR            SESSION_TYPE          SID
---------- -------------------- ---------- ---------------- -------------- ----------
ADMIN      SYS_EXPORT_SCHEMA_01          3 000000117DFA3548 DBMS_DATAPUMP       11284
ADMIN      SYS_EXPORT_SCHEMA_01          3 00000011384B0EE8 WORKER              31700
ADMIN      SYS_EXPORT_SCHEMA_01          3 000000112C48EE08 MASTER              34504
*/

----------------------------------------------------------------------------------------------------
--stop all jobs
----------------------------------------------------------------------------------------------------
DECLARE
  h NUMBER;
BEGIN
  FOR i IN (SELECT DISTINCT owner_name, job_name FROM dba_datapump_jobs
  WHERE state = 'NOT RUNNING') 
  LOOP
    -- Attach to running job by name
    h := DBMS_DATAPUMP.ATTACH(job_name => i.owner_name||'.'||i.job_name);

    -- Stop gracefully (Data Pump cleans up temporary objects)
    DBMS_DATAPUMP.STOP_JOB(handle => h);
    
    DBMS_DATAPUMP.DETACH(h);
  END LOOP;
END;
/


----------------------------------------------------------------------------------------------------
--wait for running jobs
--ORA-31626: job does not exist
----------------------------------------------------------------------------------------------------
CLEAR SCREEN
DECLARE
  h NUMBER;
  l_job_name VARCHAR2(100);
  l_job_state VARCHAR2(100);
  e_job_does_not_exists EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_job_does_not_exists,-31626
  );

BEGIN
  FOR i IN (SELECT DISTINCT owner_name, job_name FROM dba_datapump_jobs) 
  LOOP
    BEGIN
      l_job_name := i.owner_name||'.'||i.job_name;
      -- Attach to running job by name
      h := DBMS_DATAPUMP.ATTACH(job_name => l_job_name);

      -- Stop gracefully (Data Pump cleans up temporary objects)
      DBMS_DATAPUMP.WAIT_FOR_JOB(handle => h, job_state => l_job_state);
	  dbms_output.put_line('Datapump Job: '||l_job_name||', Status: '||l_job_state);
    
      DBMS_DATAPUMP.DETACH(h);
	EXCEPTION 
	  WHEN e_job_does_not_exists THEN 
	    dbms_output.put_line('Datapump Job: '||l_job_name||' does not exist');
	END;
  END LOOP;
END;
/



----------------------------------------------------------------------------------------------------
-- spool data pump log file out
----------------------------------------------------------------------------------------------------
SET SERVEROUTPUT ON SIZE UNLIMITED echo on;
clear screen
DECLARE
    l_file   UTL_FILE.FILE_TYPE;
    l_line   VARCHAR2(32767);
    l_dir    CONSTANT VARCHAR2(30) := 'DATA_PUMP_DIR';
BEGIN
  FOR i IN (
    SELECT * FROM TABLE(DBMS_CLOUD.LIST_FILES('DATA_PUMP_DIR'))
	WHERE object_name like 'export_strava%.log'
  ) LOOP
    BEGIN
      -- Open the file for reading
      l_file := UTL_FILE.FOPEN(location => l_dir,
                               filename => i.object_name,
                               open_mode => 'R',
                               max_linesize => 32767);

      -- Loop through each line
      LOOP
        BEGIN
            UTL_FILE.GET_LINE(l_file, l_line);
            DBMS_OUTPUT.PUT_LINE(l_line);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                EXIT;  -- exit loop at end of file
        END;
      END LOOP;
      -- Close the file
      UTL_FILE.FCLOSE(l_file);
    EXCEPTION
      WHEN UTL_FILE.INVALID_PATH THEN
        DBMS_OUTPUT.PUT_LINE('Invalid directory path: ' || l_dir);
      WHEN UTL_FILE.INVALID_MODE THEN
        DBMS_OUTPUT.PUT_LINE('Invalid mode for file: ' || i.object_name);
      WHEN UTL_FILE.READ_ERROR THEN
        DBMS_OUTPUT.PUT_LINE('Read error on file: ' || i.object_name);
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Unexpected error: ' || SQLERRM);
    END;
  END LOOP;

END;
/


/*
SQL> CLEAR SCREEN
SQL> DECLARE
  2    h NUMBER;
  3    l_job_name VARCHAR2(100);
  4    l_job_state VARCHAR2(100);
  5    e_job_does_not_exists EXCEPTION;
  6    PRAGMA EXCEPTION_INIT(e_job_does_not_exists,-31626);
  7  
  8  BEGIN
  9    FOR i IN (SELECT DISTINCT owner_name, job_name FROM dba_datapump_jobs) 
 10    LOOP
 11      BEGIN
 12        l_job_name := i.owner_name||'.'||i.job_name;
 13        -- Attach to running job by name
 14        h := DBMS_DATAPUMP.ATTACH(job_name => l_job_name);
 15  
 16        -- Stop gracefully (Data Pump cleans up temporary objects)
 17        DBMS_DATAPUMP.WAIT_FOR_JOB(handle => h, job_state => l_job_state);
 18  	  dbms_output.put_line('Datapump Job: '||l_job_name||', Status: '||l_job_state);
 19  
 20        DBMS_DATAPUMP.DETACH(h);
 21  	EXCEPTION 
 22  	  WHEN e_job_does_not_exists THEN 
 23  	    dbms_output.put_line('Datapump Job: '||l_job_name||' does not exist');
 24  	END;
 25    END LOOP;
 26  END;
 27  /
Datapump Job: ADMIN.SYS_EXPORT_FULL_01 does not exist
Datapump Job: ADMIN.SYS_EXPORT_FULL_02 does not exist


PL/SQL procedure successfully completed.

SQL> DECLARE
  2      l_file   UTL_FILE.FILE_TYPE;
  3      l_line   VARCHAR2(32767);
  4      l_dir    CONSTANT VARCHAR2(30) := 'DATA_PUMP_DIR';
  5  BEGIN
  6    FOR i IN (
  7      SELECT * FROM TABLE(DBMS_CLOUD.LIST_FILES('DATA_PUMP_DIR'))
  8  	WHERE object_name like 'export_strava%.log'
  9    ) LOOP
 10      BEGIN
 11        -- Open the file for reading
 12        l_file := UTL_FILE.FOPEN(location => l_dir,
 13                                 filename => i.object_name,
 14                                 open_mode => 'R',
 15                                 max_linesize => 32767);
 16  
 17        -- Loop through each line
 18        LOOP
 19          BEGIN
 20              UTL_FILE.GET_LINE(l_file, l_line);
 21              DBMS_OUTPUT.PUT_LINE(l_line);
 22          EXCEPTION
 23              WHEN NO_DATA_FOUND THEN
 24                  EXIT;  -- exit loop at end of file
 25          END;
 26        END LOOP;
 27        -- Close the file
 28        UTL_FILE.FCLOSE(l_file);
 29      EXCEPTION
 30        WHEN UTL_FILE.INVALID_PATH THEN
 31          DBMS_OUTPUT.PUT_LINE('Invalid directory path: ' || l_dir);
 32        WHEN UTL_FILE.INVALID_MODE THEN
 33          DBMS_OUTPUT.PUT_LINE('Invalid mode for file: ' || i.object_name);
 34        WHEN UTL_FILE.READ_ERROR THEN
 35          DBMS_OUTPUT.PUT_LINE('Read error on file: ' || i.object_name);
 36        WHEN OTHERS THEN
 37          DBMS_OUTPUT.PUT_LINE('Unexpected error: ' || SQLERRM);
 38      END;
 39    END LOOP;
 40  
 41  END;
 42  /
Starting "ADMIN"."SYS_EXPORT_SCHEMA_01":  
Estimate in progress using BLOCKS method...
Processing object type SCHEMA_EXPORT/TABLE/TABLE_DATA
.  estimated "STRAVA"."MY_AREAS"                           1.5 GB
.  estimated "STRAVA"."ACTIVITIES"                       540.1 MB
.  estimated "STRAVA"."STAGE_GEO_DATA"                    16.4 MB
.  estimated "STRAVA"."ACTIVITY_AREAS"                       5 MB
.  estimated "STRAVA"."MY_GEOMETRIES"                      1.9 MB
.  estimated "STRAVA"."STAGE_MY_AREAS"                     1.1 MB
.  estimated "STRAVA"."WEBHOOK_EVENTS"                     640 KB
.  estimated "STRAVA"."ALLSWAINS"                          320 KB
.  estimated "STRAVA"."API_LOG"                            320 KB
.  estimated "STRAVA"."GEAR"                               320 KB
.  estimated "STRAVA"."SCHEDULER$_JOB_ARG"                 320 KB
.  estimated "STRAVA"."MY_AREA_CODES"                      128 KB
.  estimated "STRAVA"."STRAVA_TOKENS"                       64 KB
.  estimated "STRAVA"."ACTIVITIES_EXT"                     4.7 KB
Total estimation using BLOCKS method: 2.1 GB
Processing object type SCHEMA_EXPORT/PACKAGE/PACKAGE_BODY
Processing object type SCHEMA_EXPORT/TABLE/INDEX/STATISTICS/INDEX_STATISTICS
Processing object type SCHEMA_EXPORT/TABLE/STATISTICS/TABLE_STATISTICS
Processing object type SCHEMA_EXPORT/USER
Processing object type SCHEMA_EXPORT/SYSTEM_GRANT
Processing object type SCHEMA_EXPORT/ROLE_GRANT
Processing object type SCHEMA_EXPORT/DEFAULT_ROLE
Processing object type SCHEMA_EXPORT/TABLESPACE_QUOTA
Processing object type SCHEMA_EXPORT/PASSWORD_HISTORY
Processing object type SCHEMA_EXPORT/PRE_SCHEMA/PROCACT_SCHEMA/LOGREP
Processing object type SCHEMA_EXPORT/SYNONYM/SYNONYM
Processing object type SCHEMA_EXPORT/TYPE/TYPE_SPEC
Processing object type SCHEMA_EXPORT/TYPE/GRANT/OWNER_GRANT/OBJECT_GRANT
Processing object type SCHEMA_EXPORT/SEQUENCE/SEQUENCE
Processing object type SCHEMA_EXPORT/TABLE/TABLE
Processing object type SCHEMA_EXPORT/TABLE/GRANT/OWNER_GRANT/OBJECT_GRANT
Processing object type SCHEMA_EXPORT/TABLE/IDENTITY_COLUMN
Processing object type SCHEMA_EXPORT/PACKAGE/PACKAGE_SPEC
Processing object type SCHEMA_EXPORT/FUNCTION/FUNCTION
Processing object type SCHEMA_EXPORT/PACKAGE/COMPILE_PACKAGE/PACKAGE_SPEC/ALTER_PACKAGE_SPEC
Processing object type SCHEMA_EXPORT/FUNCTION/ALTER_FUNCTION
Processing object type SCHEMA_EXPORT/VIEW/VIEW
Processing object type SCHEMA_EXPORT/TABLE/INDEX/INDEX
Processing object type SCHEMA_EXPORT/TABLE/CONSTRAINT/CONSTRAINT
Processing object type SCHEMA_EXPORT/TABLE/CONSTRAINT/REF_CONSTRAINT
Processing object type SCHEMA_EXPORT/TABLE/TRIGGER
Processing object type SCHEMA_EXPORT/TABLE/INDEX/DOMAIN_INDEX/INDEX
Processing object type SCHEMA_EXPORT/POST_SCHEMA/PROCOBJ/SCHEDULER
Processing object type SCHEMA_EXPORT/POST_SCHEMA/PROCACT_SCHEMA/SCHEDULER
Processing object type SCHEMA_EXPORT/POST_SCHEMA/PROCACT_SCHEMA/LBAC_EXP
. . exported "STRAVA"."MY_AREAS"                           646 MB  113713 rows
. . exported "STRAVA"."ACTIVITIES"                       339.9 MB    5531 rows
. . exported "STRAVA"."STAGE_GEO_DATA"                   749.1 KB       3 rows
. . exported "STRAVA"."ACTIVITY_AREAS"                     1.2 MB  129294 rows
. . exported "STRAVA"."MY_GEOMETRIES"                      8.6 KB       2 rows
. . exported "STRAVA"."STAGE_MY_AREAS"                     7.4 KB       1 rows
. . exported "STRAVA"."WEBHOOK_EVENTS"                    17.9 KB      88 rows
. . exported "STRAVA"."ALLSWAINS"                        108.7 KB    1734 rows
. . exported "STRAVA"."API_LOG"                            5.8 KB      14 rows
. . exported "STRAVA"."GEAR"                               6.3 KB      11 rows
. . exported "STRAVA"."SCHEDULER$_JOB_ARG"                 5.4 KB       4 rows
. . exported "STRAVA"."MY_AREA_CODES"                      5.7 KB      51 rows
. . exported "STRAVA"."STRAVA_TOKENS"                      5.2 KB       1 rows
. . exported "STRAVA"."ACTIVITIES_EXT"                       0 KB       0 rows
ORA-39173: Encrypted data has been stored unencrypted in dump file set.
Master table "ADMIN"."SYS_EXPORT_SCHEMA_01" successfully loaded/unloaded
Generating checksums for dump file set
******************************************************************************
Dump file set for ADMIN.SYS_EXPORT_SCHEMA_01 is:
  /u03/dbfs/4A03C84C700735C1E063D760000A3AE1/data/dpdump/export_strava_20260311_01.dmp
Job "ADMIN"."SYS_EXPORT_SCHEMA_01" successfully completed at Wed Mar 11 20:10:17 2026 elapsed 0 00:04:17


PL/SQL procedure successfully completed.

*/

----------------------------------------------------------------------------------------------------
-- copy the files to OCI bucket and delete from DATA_PUMP_DIR
----------------------------------------------------------------------------------------------------
DECLARE 
  l_counter INTEGER := 0;
  l_filename VARCHAR2(100);
  l_dir VARCHAR2(100) := 'DATA_PUMP_DIR';
  l_uri VARCHAR2(200) := 'https://objectstorage.uk-london-1.oraclecloud.com/n/lrp1qmpxv8ea/b/bucket-gofaster1/o/';
BEGIN
  FOR i IN (
    SELECT * FROM TABLE(DBMS_CLOUD.LIST_FILES('DATA_PUMP_DIR'))
    WHERE regexp_like(object_name,'export_strava.+\.(log|dmp)')
  ) LOOP
    l_counter := l_counter + 1;
    l_filename := REPLACE(i.object_name,'%T',TO_CHAR(i.created,'YYYYMMDD'));
	l_filename := REPLACE(l_filename,'%U',l_counter);
	dbms_output.put_line(l_filename);
    DBMS_CLOUD.PUT_OBJECT
    (credential_name => 'OBJECT_STORE_CRED'
    ,object_uri      => l_uri||l_filename
    ,directory_name  => l_dir
    ,file_name       => i.object_name
    );
	UTL_FILE.FREMOVE('DATA_PUMP_DIR',i.object_name);
  END LOOP;
END;
/

/*
export_strava_20260311_01.dmp
export_strava_20260311.log

PL/SQL procedure successfully completed.
*/


----------------------------------------------------------------------------------------------------
-- empty DATA_PUMP_DIR
----------------------------------------------------------------------------------------------------
BEGIN
  FOR i IN (
    SELECT * FROM TABLE(DBMS_CLOUD.LIST_FILES('DATA_PUMP_DIR'))
    WHERE regexp_like(object_name,'export_strava.+\.(log|dmp)')
  ) LOOP
	dbms_output.put_line('Deleting file '||i.object_name);
	UTL_FILE.FREMOVE('DATA_PUMP_DIR',i.object_name);
  END LOOP;
END;
/
