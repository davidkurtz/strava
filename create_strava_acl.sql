REM create_strava_acl.sql
set pages 999 lines 100 trimspool on echo on
column owner format a12
column principal format a12
column principal_type format a12 heading 'Principal|Type'
column parent_acl_owner format a10 heading 'Parent|ACL Owner'
column name format a45
column acl format a45
column parent_acl format a30
column security_class format a10 heading 'Security|Class'
column security_class_owner format a12 heading 'Security|Class Owner'
column privilege format a12
column description format a40
clear screen
spool create_strava_acl.lst
----------------------------------------------------------------------------------------------------
BEGIN
  FOR i IN(SELECT * FROM dba_host_acls where host = 'www.strava.com') LOOP
    DBMS_NETWORK_ACL_ADMIN.drop_acl(acl => i.acl);
  END LOOP;
END;
/

select * FROM dba_host_acls;
select * FROM dba_network_acls;
select * FROM dba_host_aces;
select * FROM dba_network_acl_privileges;


BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => 'www.strava.com',
    upper_port => 443,
    lower_port => 443,
    ace  => xs$ace_type(
              privilege_list => xs$name_list('connect','http'),
              principal_name => 'STRAVA',
              principal_type => xs_acl.ptype_db));
END;
/


select * FROM dba_network_acls;
----------------------------------------------------------------------------------------------------
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
	host => '*.arcgis.com',
	--host => 'data.gov.ie',
	--host => 'adresse.data.gouv.fr',
	------------------------------------------------------------
    --host => '*.data.gov.uk',
    --host => 'osm-boundaries.com',
    --host => 'simplemaps.com',
    --host => '*.opendatani.gov.uk',
	--host => '*.cloudflarestorage.com',
	--host => 'labs.karavia.ch',
    ace  => xs$ace_type(
              privilege_list => xs$name_list('connect','http'),
              principal_name => 'STRAVA',
              principal_type => xs_acl.ptype_db));
END;
/

----------------------------------------------------------------------------------------------------
BEGIN 
  FOR i IN (select * FROM dba_network_acls where acl like 'NETWORK_ACL%') LOOP
    DBMS_NETWORK_ACL_ADMIN.drop_acl(acl => i.acl);
  END LOOP;
END;
/
----------------------------------------------------------------------------------------------------
select * from DBA_XS_ACES where principal IN('ADMIN','STRAVA');
select * from dba_xs_acls where name IN (SELECT acl from DBA_XS_ACES where principal = 'STRAVA');
select * FROM dba_network_acls;
----------------------------------------------------------------------------------------------------
spool off
