REM reprocess_multi_country_activities.sql

update activities
set processing_status = 4
where processing_status between 5 and 8
and activity_id IN(
  select aa.activity_id
  from activity_areas aa 
    INNER JOIN my_areas ma ON ma.area_code = aa.area_code AND ma.area_number = aa.area_number
  WHERE aa.area_code IN('SOVC','GEOU')
  --AND ma.parent_area_code IS NULL
  --AND ma.parent_area_number IS NULL
  GROUP BY aa.activity_id
  HAVING COUNT(*)>1
  )
/

select 
from activities
/

select * from my_areas where name = 'Scotland';

--test area_list
    SELECT a.activity_id
    ,      listagg(DISTINCT ma.name,', ') within group (order by ma.name_hierarchy) area_list
    FROM   activities a
      INNER JOIN activity_areas aa on a.activity_id = aa.activity_id
      INNER JOIN my_areas ma on ma.area_code = aa.area_code and ma.area_number = aa.area_number
	  --INNER JOIN my_area_codes mac ON mac.area_code = ma.area_code
    WHERE a.activity_id = 7071640890
	--AND a.processing_status = k4_status_areas_processed
	and ma.matchable = 1
    GROUP BY a.activity_id
/

