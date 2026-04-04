REM fix_siblings.sql
----------------------------------------------------------------------------------------------------
--if one sibling covers another  make it the parent
----------------------------------------------------------------------------------------------------
merge into my_areas u
using (
select p.area_Code parent_area_Code, p.area_number parent_area_number, p.name parent_name
,      c.area_code, c.area_number, c.name
    ,      sdo_geom.relate(p.geom,'determine',c.geom) relationship
--    ,      sdo_geom.sdo_area(p.geom, unit=>'unit=sq_km') p_kmsq
--    ,      sdo_geom.sdo_area(c.geom, unit=>'unit=sq_km') c_kmsq
--    ,      sdo_geom.sdo_area(sdo_geom.sdo_intersection(p.geom,c.geom,1), unit=>'unit=sq_km') i_kmsq
from my_areas p, my_areas c
where p.parent_area_code = c.parent_area_code
and p.parent_area_number = c.parent_area_number
and (p.rowid != c.rowid) --not the same row
and (p.area_code != c.area_code) --not the same type of area
--and sdo_geom.relate(p.mbr,'determine',c.mbr) = 'COVERS'
and sdo_geom.relate(p.geom,'determine',c.geom) = 'COVERS'
--and    SDO_ANYINTERACT(p.geom, c.geom)
and    SDO_ANYINTERACT(p.mbr, c.mbr) 
--and (p.name like c.name||'%' or c.name like p.name||'%')
and c.area_code IN('CPC') and p.area_code IN('UTW','MTW','DIW') 
--and p.area_code IN('CPC') and c.area_code IN('UTW','MTW','DIW') 
--and p.area_code IN('DIW') and c.area_code IN('CPC') and c.name like 'F%' and p.name like 'F%' 
fetch first 2000 rows only
) s
on (u.area_code = s.area_code AND u.area_number = s.area_Number)
WHEN MATCHED THEN UPDATE 
SET u.parent_area_code = s.parent_area_code
, u.parent_area_number = s.parent_area_number
/

----------------------------------------------------------------------------------------------------
--correct count of number of children
----------------------------------------------------------------------------------------------------
merge into my_areas u
using (
select p.area_code, p.area_number, p.name, p.num_children, count(c.area_number) child_count
from my_areas p
  left outer join my_areas c
    on p.area_code = c.parent_area_code
    and p.area_number = c.parent_area_number
where 1=1
--and c.num_children IS NULL
group by p.area_code, p.area_number, p.name, p.num_children
having count(c.area_number) != NVL(p.num_children,0)
) s
ON (s.area_code = u.area_code AND s.area_number = u.area_number)
WHEN MATCHED THEN UPDATE 
SET u.num_children = s.child_count
/

----------------------------------------------------------------------------------------------------
-- correct parent uqid 
----------------------------------------------------------------------------------------------------
merge into my_areas u
using (
select c.area_code, c.area_number, c.parent_uqid, p.uqid 
from my_areas c
  inner join my_areas p on p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
where c.parent_uqid != p.uqid
) s
ON (s.area_code = u.area_code AND s.area_number = u.area_number)
WHEN MATCHED THEN UPDATE 
SET u.parent_uqid = s.uqid
/

select parent_area_Code, area_code, count(*) num_areas
from my_areas
where last_updated > sysdate-.1
group by area_Code, parent_Area_code
/