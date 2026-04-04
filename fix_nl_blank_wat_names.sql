update my_areas c
set name = (SELECT name FROM my_areas p where p.area_code = c.parent_Area_code and p.area_number = c.parent_Area_number)
where name IS NULL
and parent_area_code ='WAT'
and area_code = 'WAT'
/