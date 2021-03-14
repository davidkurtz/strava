REM text_index.sql
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
--test area_heirarchy procedure
set serveroutput on
DECLARE
  l_rowid ROWID;
  l_clob CLOB;
BEGIN
  select rowid
  into   l_rowid
  FROM   my_areas m
  WHERE  area_code = 'CPC'
  And    area_number = '40307';

  strava_pkg.area_heirarchy(l_rowid, l_clob);
  dbms_output.put_line(l_clob);
END;
/

----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
--build text index
Exec ctx_ddl.drop_preference('my_areas_lexer');  
Exec ctx_ddl.drop_preference('my_areas_datastore'); 

begin
 ctx_ddl.create_preference('my_areas_lexer', 'BASIC_LEXER');  
 ctx_ddl.set_attribute('my_areas_lexer', 'mixed_case', 'NO'); 
end;
/
begin
  ctx_ddl.create_preference('my_areas_datastore', 'user_datastore'); 
  ctx_ddl.set_attribute('my_areas_datastore', 'procedure', 'strava_pkg.area_heirarchy'); 
  ctx_ddl.set_attribute('my_areas_datastore', 'output_type', 'CLOB');
end;
/

drop index my_areas_names_txtidx;
create index my_areas_names_txtidx on my_areas (name) indextype is ctxsys.context 
parameters ('datastore my_areas_datastore lexer my_areas_lexer');
-- sync(on commit) -- wont sync on commit because could be affected by hierarchy changes

--manual sync
exec ctx_ddl.sync_index('my_areas_names_txtidx');


----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
set lines 180
select score(1), area_Code, area_number, name, matchable, parent_area_code, parent_area_number, area_level, sdo_geom.sdo_area(geom) area
from my_areas m
--where contains(name,'streatley',1)>0
--where contains(name,'streatley and berkshire',1)>0
--where contains(name,'west berkshire',1)>0
--where contains(name,'lairg',1)>0
where contains(name,'meriden',1)>0
order by name
/

