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
exec DBMS_NETWORK_ACL_ADMIN.drop_acl(acl => 'strava_acl.xml');
select * FROM dba_network_acls;

BEGIN
  DBMS_NETWORK_ACL_ADMIN.create_acl (
    acl          => 'strava_acl.xml',
    description  => 'Allow access to Strava API',
    principal    => 'STRAVA',   -- your DB user
    is_grant     => TRUE,
    privilege    => 'connect'
  );
END;
/
BEGIN
  DBMS_NETWORK_ACL_ADMIN.add_privilege (
    acl          => 'strava_acl.xml',
    principal    => 'STRAVA',   -- your DB user
    is_grant     => TRUE,
    privilege    => 'http'
  );
END;
/
BEGIN
  DBMS_NETWORK_ACL_ADMIN.assign_acl (
    acl  => 'strava_acl.xml',
    host => 'www.strava.com'
  );
END;
/
select * FROM dba_network_acls;
----------------------------------------------------------------------------------------------------
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => 'data-osi.opendata.arcgis.com',
	--host => '*.arcgis.com',
	------------------------------------------------------------
	--host => 'data.gov.ie',
	--host => 'data-sdublincoco.opendata.arcgis.com',
    --host => 'hub.arcgis.com',
	--host => 'tg-arcgisazurecdataprodeu1.az.arcgis.com',
    --host => 'osm-boundaries.com',
    --host => 'simplemaps.com',
    --host => '*.arcgis.com',
    --host => '*.opendatani.gov.uk',
    --host => '*.data.gov.uk',
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
