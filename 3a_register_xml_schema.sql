REM 3a_register_xml_schema.sql
spool 3a_register_xml_schema
connect strava/strava@oracle_pdb
set serveroutput on

delete from plan_table WHERE statement_id = 'XSD';
insert into plan_table (statement_id, plan_id, object_name, object_alias)
values ('XSD', 1, 'gpx0.xsd', 'http://www.topografix.com/GPX/1/0/gpx.xsd');
insert into plan_table (statement_id, plan_id, object_name, object_alias)
values ('XSD', 2, 'gpx.xsd', 'http://www.topografix.com/GPX/1/1/gpx.xsd');
insert into plan_table (statement_id, plan_id, object_name, object_alias)
values ('XSD', 3, 'TrackPointExtensionv1.xsd', 'https://www8.garmin.com/xmlschemas/TrackPointExtensionv1.xsd');

DECLARE
  xmlSchema xmlType;
  res       boolean;
BEGIN
  FOR i IN (
    SELECT object_alias schemaURL
    ,      object_name  schemaDoc
    FROM   plan_table
    WHERE  statement_id = 'XSD'
    ORDER BY plan_id
  ) LOOP
    --read xsd file
    xmlSchema := XMLTYPE(getCLOBDocument('STRAVA',i.schemaDoc,'AL32UTF8'));
    --if already exists delete XSD
    if (dbms_xdb.existsResource(i.schemaDoc)) then
        dbms_xdb.deleteResource(i.schemaDoc);
    end if;
    --create resource from XSD
    res := dbms_xdb.createResource(i.schemaDoc,xmlSchema);

    -- Delete existing  schema
    dbms_xmlschema.deleteSchema(
      i.schemaURL
    );
    -- Now reregister the schema
    dbms_xmlschema.registerSchema(
      i.schemaURL,
      xmlSchema,
      TRUE,TRUE,FALSE,FALSE
    );
  END LOOP;
End;
/

-- Queries to see if it exists
Set pages 99 lines 160
Column schema_url format a45
select schema_url, local, hier_type, binary, qual_schema_url
from user_xml_schemas
/
spool off
