REM adb_datapump_import.sql
clear screen
set echo on serveroutput on 
----------------------------------------------------------------------------------------------------
-- list the files in the bucket does not work
----'https://lrp1qmpxv8ea.objectstorage.uk-london-1.oci.customer-oci.com/p/pWn6XY6QIIy_oRj5HFLiPD5pyU8ICOFTzowfBj5Qo-kFVUMEeN2R6W6oZiCiMRgC/n/lrp1qmpxv8ea/b/bucket-gofaster1/o/?par=par-bucket-20260311-1945';
--select * from dba_credentials;
--desc dbms_cloud
--------------------------------------------------------------------------------------------------
DECLARE
  l_uri VARCHAR2(200) := 'https://objectstorage.uk-london-1.oraclecloud.com/n/lrp1qmpxv8ea/b/bucket-gofaster1/o/';
BEGIN
  -- List objects in bucket to verify access
  DBMS_OUTPUT.PUT_LINE('Listing objects in bucket:'||l_uri);
  FOR r IN (
    SELECT * FROM TABLE(
      DBMS_CLOUD.LIST_OBJECTS
	  (credential_name => 'OBJECT_STORE_CRED'
      ,location_uri    => l_uri
      )
    )
  ) LOOP
    DBMS_OUTPUT.PUT_LINE(r.object_name);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Bucket listing completed successfully.');
END;
/

----------------------------------------------------------------------------------------------------
-- move the file into local dir
----------------------------------------------------------------------------------------------------
DECLARE
  l_filename VARCHAR2(100) := 'export_strava_20260311_01.dmp';
  l_uri VARCHAR2(200) := 'https://lrp1qmpxv8ea.objectstorage.uk-london-1.oci.customer-oci.com/p/pWn6XY6QIIy_oRj5HFLiPD5pyU8ICOFTzowfBj5Qo-kFVUMEeN2R6W6oZiCiMRgC/n/lrp1qmpxv8ea/b/bucket-gofaster1/o/';
BEGIN
  DBMS_CLOUD.GET_OBJECT
  (object_uri      => l_uri||l_filename
  ,directory_name  => 'DATA_PUMP_DIR'
  );
END;
/
SELECT * FROM TABLE(DBMS_CLOUD.LIST_FILES('DATA_PUMP_DIR'));



----------------------------------------------------------------------------------------------------
REM import data pump export  into schema 
----------------------------------------------------------------------------------------------------
DECLARE
  h NUMBER;
  l_file_name VARCHAR2(100) := 'export_strava_20260311_01';
  l_dir VARCHAR2(100) := 'DATA_PUMP_DIR';
BEGIN
  h := DBMS_DATAPUMP.OPEN
  (operation => 'IMPORT'
  --,job_mode  => 'SCHEMA'
  ,job_mode  => 'TABLE'
  );

  DBMS_DATAPUMP.ADD_FILE
  (handle    => h
  ,filename  => l_file_name||'.dmp'
  ,directory => l_dir
  ,filetype => DBMS_DATAPUMP.KU$_FILE_TYPE_DUMP_FILE
  );

  DBMS_DATAPUMP.ADD_FILE
  (handle    => h
  ,filename  => l_file_name||'.import.log'
  ,directory => l_dir
  ,filetype  => DBMS_DATAPUMP.KU$_FILE_TYPE_LOG_FILE
  ,reusefile => 1
  );
 
  DBMS_DATAPUMP.METADATA_FILTER
  (handle => h
  ,name   => 'SCHEMA_EXPR'
  ,value  => 'IN (''STRAVA'')'
  );

  DBMS_DATAPUMP.METADATA_FILTER
  (handle => h
  ,name   => 'NAME_EXPR'
  ,value  => 'IN (''STAGE_GEO_DATA'')'
  );

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
-- copy the files to OCI bucket and delete from DATA_PUMP_DIR
----------------------------------------------------------------------------------------------------
DECLARE 
  l_counter INTEGER := 0;
  l_filename VARCHAR2(100);
  l_dir VARCHAR2(100) := 'DATA_PUMP_DIR';
  l_uri VARCHAR2(200) := 'https://lrp1qmpxv8ea.objectstorage.uk-london-1.oci.customer-oci.com/p/pWn6XY6QIIy_oRj5HFLiPD5pyU8ICOFTzowfBj5Qo-kFVUMEeN2R6W6oZiCiMRgC/n/lrp1qmpxv8ea/b/bucket-gofaster1/o/';
BEGIN
  FOR i IN (
    SELECT * FROM TABLE(DBMS_CLOUD.LIST_FILES('DATA_PUMP_DIR'))
    WHERE regexp_like(object_name,'export_strava.+\.(log)')
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


