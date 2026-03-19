REM activities_area_list.sql

GRANT EXECUTE ON CTX_DDL TO strava;

/*
alter table activities 
add (area_list clob)
LOB(area_list) STORE AS SECUREFILE activities_area_list (DEDUPLICATE COMPRESS)
*/


merge into activities u 
using (
SELECT a.activity_id, LISTAGG(DISTINCT ma.name,', ') WITHIN GROUP (ORDER BY ma.name) area_list
FROM   activities a, my_areas ma, activity_areas aa
WHERE  ma.area_code = aa.area_code
AND    ma.area_number = aa.area_number
AND    aa.activity_id = a.activity_id
and    a.area_list IS NULL
group by a.activity_id
) s on (s.activity_id = u.activity_id)
WHEN MATCHED THEN UPDATE
SET u.area_list = s.area_list
/
commit
/

Exec ctx_ddl.drop_preference('activities_lexer');  
Exec ctx_ddl.drop_preference('activities_datastore'); 

begin
 ctx_ddl.create_preference('activities_lexer', 'BASIC_LEXER');  
 ctx_ddl.set_attribute('activities_lexer', 'mixed_case', 'NO'); 
 ctx_ddl.create_preference('activities_datastore', 'DIRECT_DATASTORE'); 
--ctx_ddl.set_attribute('activities_datastore', 'columns', 'area_list'); 
end;
/

drop index activities_area_list_txtidx;
create index activities_area_list_txtidx on activities (area_list) indextype is ctxsys.context 
parameters ('datastore activities_datastore lexer activities_lexer sync(on commit)');

exec ctx_ddl.sync_index('activities_area_list_txtidx');
