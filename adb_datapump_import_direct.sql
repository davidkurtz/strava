REM adb_datapump_import_direct.sql
clear screen
set echo on serveroutput on pages 999 lines 200 trimspool on
----------------------------------------------------------------------------------------------------
-- list the files in the bucket does not work
----'https://lrp1qmpxv8ea.objectstorage.uk-london-1.oci.customer-oci.com/p/pWn6XY6QIIy_oRj5HFLiPD5pyU8ICOFTzowfBj5Qo-kFVUMEeN2R6W6oZiCiMRgC/n/lrp1qmpxv8ea/b/bucket-gofaster1/o/?par=par-bucket-20260311-1945';
--select * from dba_credentials;
--desc dbms_cloud
--------------------------------------------------------------------------------------------------
--if you specify this, you dont need to specify a ccredential!!!
ALTER DATABASE PROPERTY SET DEFAULT_CREDENTIAL = 'ADMIN.OBJECT_STORE_CRED';
column object_name format a60
SELECT object_name, bytes/1024/1024 Mb
FROM table(
  DBMS_CLOUD.LIST_objects
  (--credential_name => 'OBJECT_STORE_CRED',
   location_uri => 'https://objectstorage.uk-london-1.oraclecloud.com/n/lrp1qmpxv8ea/b/bucket-gofaster1/o/'
  ));




----------------------------------------------------------------------------------------------------
REM import data pump export  into schema 
----------------------------------------------------------------------------------------------------
clear screen
DECLARE
  h NUMBER;
  l_file_name VARCHAR2(100) := 'export_strava_20260428_01.dmp';
  l_urifile_name VARCHAR2(200);
  l_dir VARCHAR2(100) := 'DATA_PUMP_DIR';
BEGIN
  l_urifile_name := 'https://objectstorage.uk-london-1.oraclecloud.com/n/lrp1qmpxv8ea/b/bucket-gofaster1/o/'
                    ||l_file_name;
  h := DBMS_DATAPUMP.OPEN
  (operation => 'IMPORT'
  ,job_mode  => 'SCHEMA'
  );

  DBMS_DATAPUMP.ADD_FILE
       (handle    => h
       ,filename  => l_urifile_name
    ,filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_URIDUMP_FILE
    ,directory => 'OBJECT_STORE_CRED'
    --,credential_name => 'OBJECT_STORE_CRED'
  );

  DBMS_DATAPUMP.ADD_FILE
  (handle    => h
  ,filename  => 'import_strava.log'
  ,directory => l_dir
  ,filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_LOG_FILE
  ,reusefile => 1
  );
 
  DBMS_DATAPUMP.METADATA_FILTER
  (handle => h
  ,name   => 'SCHEMA_EXPR'
  ,value  => 'IN (''STRAVA'')'
  );
  /* 
  DBMS_DATAPUMP.METADATA_FILTER
  (handle => h
  ,name   => 'NAME_EXPR'
  ,value  => 'IN (''API_LOG'')'
  );
  */
  dbms_datapump.set_parameter
  (handle => h
  ,name   => 'TABLE_EXISTS_ACTION'
  ,value  => 'TRUNCATE'
  );

  DBMS_DATAPUMP.START_JOB(h);
  DBMS_DATAPUMP.DETACH(h);
END;
/

----------------------------------------------------------------------------------------------------
-- see what is running
----------------------------------------------------------------------------------------------------
column owner_name format a10
column job_name format a20
column operation format a10
column job_mode format a10
column state format a12
select * from dba_datapump_jobs
/

select *
from dba_datapump_sessions p
  left outer join gv$session s on s.inst_id = p.inst_id and s.saddr = p.saddr
/


select * from strava.stage_geo_data
/
----------------------------------------------------------------------------------------------------
--list job status and stop it (in comments)
----------------------------------------------------------------------------------------------------
clear screen
set echo on serveroutput on
DECLARE
  h NUMBER;
  job_state VARCHAR2(100);
  status ku$_Status;
BEGIN
  h := dbms_datapump.attach(job_name  => 'IMP_TABLE_JOB1', job_owner=>'ADMIN');
  
  DBMS_DATAPUMP.get_status
  (handle=>h
  ,mask => DBMS_DATAPUMP.ku$_status_job_error 
         + DBMS_DATAPUMP.ku$_status_job_status 
         + DBMS_DATAPUMP.ku$_status_wip
  ,timeout=>0
  ,job_state=>job_state
  ,status => status
  );
  
  dbms_output.put_line('Job State:'||job_state);
/*
  DBMS_DATAPUMP.stop_job
  (handle=>h
  ,immediate=>1
   );
*/
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
	WHERE object_name like 'import_strava%.log'
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

----------------------------------------------------------------------------------------------------
-- copy the files to OCI bucket and delete from DATA_PUMP_DIR
----------------------------------------------------------------------------------------------------
DECLARE 
  l_counter INTEGER := 0;
  l_filename VARCHAR2(100);
  l_dir VARCHAR2(100) := 'DATA_PUMP_DIR';
  l_uri VARCHAR2(200) := 'https://objectstorage.uk-london-1.oraclecloud.com/n/lrp1qmpxv8ea/b/bucket-gofaster1/o//';
BEGIN
  FOR i IN (
    SELECT * FROM TABLE(DBMS_CLOUD.LIST_FILES('DATA_PUMP_DIR'))
    WHERE regexp_like(object_name,'import_strava.(log)')
  ) LOOP
    l_counter := l_counter + 1;
    l_filename := i.object_name;
	dbms_output.put_line(l_filename);
    DBMS_CLOUD.PUT_OBJECT
    (object_uri      => l_uri||l_filename
    ,directory_name  => l_dir
    ,file_name       => i.object_name
    );
	UTL_FILE.FREMOVE(l_dir,i.object_name);
  END LOOP;
END;
/
----------------------------------------------------------------------------------------------------
SELECT * FROM TABLE(DBMS_CLOUD.LIST_FILES('DATA_PUMP_DIR'))
/

select owner, object_type, count(*)
from dba_objects
where owner = 'STRAVA'
group by owner, object_Type
order by 3 desc 
/
select owner, segment_type, tablespace_name
, count(*), sum(bytes)/1024/1024 Mb
from dba_segments
where owner = 'STRAVA'
group  by owner, segment_type, tablespace_name
/


