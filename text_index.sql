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
--build text index with user_datastore
Exec ctx_ddl.drop_preference('my_areas_lexer');  
Exec ctx_ddl.drop_preference('my_areas_datastore'); 
drop index my_areas_names_txtidx;

begin
 ctx_ddl.create_preference('my_areas_lexer', 'BASIC_LEXER');  
 ctx_ddl.set_attribute('my_areas_lexer', 'mixed_case', 'NO'); 
end;
/
begin
  ctx_ddl.create_preference('my_areas_datastore', 'user_datastore'); 
  ctx_ddl.set_attribute('my_areas_datastore', 'procedure', 'strava_pkg.name_heirarchy_txtidx'); 
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
column area_Code heading 'Area|Code'
column area_number heading 'Area|Number' 
column suffix format a10
column name format a25
column name_heirarchy format a75
column matchable heading 'Match|-able' format 9
select score(1), area_Code, area_number, name, matchable
--, parent_area_code, parent_area_number, area_level
--, sdo_geom.sdo_area(geom) area
, name_heirarchy
from my_areas m
--where contains(name,'streatley',1)>0
--where contains(name,'streatley and berkshire',1)>0
where contains(name,'Twyford',1)>0
--where contains(name,'berkshire',1)>0
--where contains(name,'lairg',1)>0
--where contains(name,'meriden',1)>0
and matchable = 1
order by name
/

--drop table tmp_search_results;
create global temporary table tmp_search_results
(area_Code varchar2(4) not null
,area_number integer not null
,score integer
,constraint tmp_search_results_pk primary key (area_code, area_number)
);

set lines 180
column name_heirarchy format a80
select score(1), area_Code, area_number, name, suffix, name_heirarchy
from my_areas m
--where contains(name,'streatley',1)>0
--where contains(name,'streatley and berkshire',1)>0
where contains(name,'berkshire',1)>0
/

rollback;
insert into tmp_search_results
select area_Code, area_number, score(1)
from my_areas m
where contains(name,'berkshire',1)>0
--where contains(name,'Devon',1)>0
--where contains(name,'England',1)>0
and matchable = 1
/

delete from tmp_search_results c
where exists(
select  1
from	my_areas m
,       tmp_search_results p
where   c.area_code = m.area_code
and     c.area_number = m.area_number
and     p.area_code = m.parent_area_code
and     p.area_number = m.parent_area_number)
/

select c.*, m.name_heirarchy
from   tmp_search_results c
,      my_areas m
where  c.area_code = m.area_code
and    c.area_number = m.area_number
/
