REM fix_my_areas.sql
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
exec dbms_stats.gather_table_stats(user,'my_areas');

--count number of children
update my_areas p
set p.num_children = (select NULLIF(count(*),0)
  from my_areas c
  where c.parent_area_Code = p.area_Code
  and   c.parent_area_number = p.area_number
  and   c.parent_uqid = p.uqid)
/
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
--identify areas with same name and same parents --make CPC children of Wards where covered by wards
column mbr_rel format a10
column geom_rel format a10
merge into my_areas u
using (
select m1.area_code parent_area_code, m1.area_number parent_area_number, m1.uqid parent_uqid
,      m1.name
,      m2.area_Code, m2.area_number, m2.uqid
,      SDO_GEOM.RELATE(m1.geom,'determine',m2.geom) geom_rel
from   my_areas m1
,      my_areas m2
where  m1.name = m2.name
and    m1.area_code != m2.area_code
and    m1.parent_area_code = m2.parent_area_code
and    m1.parent_area_number = m2.parent_area_number
and    m1.area_code NOT IN('AONB','CPC')
and    m2.area_code IN('CPC')
and    SDO_ANYINTERACT(m1.geom, m2.geom) = 'TRUE'
--and    SDO_GEOM.RELATE(m1.mbr,'COVERS+EQUAL',m2.mbr) = 'COVERS+EQUAL'
and    SDO_GEOM.RELATE(m1.geom,'COVERS+EQUAL',m2.geom) = 'COVERS+EQUAL'
--and    m1.name = 'Meriden'
--and rownum <= 100
) s 
ON (u.area_Code = s.area_code
AND u.area_number = s.area_number)
WHEN MATCHED THEN UPDATE
SET u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/

--find other areas with matching names where one covers the other and match the covering the parent of the covered  by
merge into my_areas u
using (
select m1.area_code parent_area_code, m1.area_number parent_area_number, m1.uqid parent_uqid
,      m1.name
,      m2.area_Code, m2.area_number, m2.uqid
,      SDO_GEOM.RELATE(m1.geom,'determine',m2.geom) geom_rel
from   my_areas m1
,      my_areas m2
where  m1.name = m2.name
and    m1.area_code != m2.area_code
and    m1.parent_area_code = m2.parent_area_code
and    m1.parent_area_number = m2.parent_area_number
and    m1.area_code NOT IN('AONB')
and    m2.area_code NOT IN('AONB')
and    SDO_ANYINTERACT(m1.geom, m2.geom) = 'TRUE'
--and    SDO_GEOM.RELATE(m1.mbr,'COVERS+EQUAL',m2.mbr) = 'COVERS+EQUAL'
and    SDO_GEOM.RELATE(m1.geom,'COVERS+EQUAL',m2.geom) = 'COVERS+EQUAL'
) s 
ON (u.area_Code = s.area_code
AND u.area_number = s.area_number)
WHEN MATCHED THEN UPDATE
SET u.parent_area_code = s.parent_area_code
,   u.parent_area_number = s.parent_area_number
,   u.parent_uqid = s.parent_uqid
/



----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------



--identify children with same name - no point adding them to activity_areas, but need to drill into their children
select c.parent_area_code, c.parent_area_number, p.num_children, c.name, c.area_code, c.area_number, c.matchable, c.num_children
from my_areas p, my_areas c
where p.area_code = c.parent_area_code
and p.area_number = c.parent_area_number
and p.name = c.name
and c.matchable >0
order by c.name
/

--by default all areas are matchable
update my_areas
set matchable=1
where matchable is null;

--mark child as unmatchable when name same as parent
update my_areas u 
SET u.matchable = 0
where (area_code, area_number) IN(
select /*p.area_code parent_area_code, p.area_number parent_area_number 
, p.name parent_name, p.num_children, sdo_geom.sdo_area(p.geom, unit=>'unit=SQ_KM') p_area,*/
 c.area_code, c.area_number /*, sdo_geom.sdo_area(c.geom, unit=>'unit=SQ_KM') c_Area*/
from my_areas p, my_areas c
where p.area_code = c.parent_area_code
and p.area_number = c.parent_area_number
and p.name = c.name
and c.matchable = 1
and (c.num_children = 0 OR c.num_children IS NULL)
) 
/

--delete any activity areas matched to areas whose parent has the same name
delete from activity_areas
where (area_code, area_number) IN (
select m.area_code, m.area_number --, m.name
from my_areas m, activity_areas a
where a.area_code = m.area_Code
and a.area_number = m.area_number
and m.matchable = 0
group by m.area_code, m.area_number, m.name)
/

--any activity_areas for which no parent area recorded
insert into activity_areas (activity_id, area_code, area_number)
select DISTINCT c2.activity_id, p1.area_code, p1.area_number
from   my_areas c1, activity_areas c2
,      my_areas p1, activity_areas p2
where  1=1
and    c1.area_code = c2.area_code
and    c1.area_number = c2.area_number
and    p1.area_code = c1.parent_area_Code
and    p1.area_number = c1.parent_area_number
and    p1.area_code = p2.area_code(+)
and    p1.area_number = p2.area_number(+)
and    p2.area_code is null
/


----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------

--REM simplify activities with >100 pts/km and >10000 points to reduce processing time
update activities
set geom       = sdo_util.simplify(geom,1)
,   geom_27700 = sdo_util.simplify(geom_27700,1)
,   num_pts    = sdo_util.getnumvertices(sdo_util.simplify(geom,1))
where num_pts > 10000
and num_pts>100*distance_km
/

--REM simplify activities with >300 pts/km and >1000 points to reduce processing time
update activities
set geom       = sdo_util.simplify(geom,1)
,   geom_27700 = sdo_util.simplify(geom_27700,1)
,   num_pts    = sdo_util.getnumvertices(sdo_util.simplify(geom,1))
where num_pts > 1000
and num_pts>250*distance_km
/

column activity_name format a60
column ppkm format 9999
select activity_id, activity_date, activity_name, distance_km, num_pts, num_pts/distance_km ppkm, power(num_pts,2)/power(distance_km,3) q
, sdo_geom.sdo_length(geom, unit=>'unit=km')  calc_km
, sdo_util.getnumvertices(geom) actual_pts
, sdo_util.getnumvertices(sdo_util.simplify(geom,1)) simp_pts
from activities
where num_pts > 1000
and num_pts>250*distance_km
order by q
/



----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
--simplifying UK areas to reduce number of points before conversion to 4326

update my_areas s
set num_pts = SDO_UTIL.GETNUMVERTICES(geom)
where num_pts IS NULL
and geom is not null
/

--simplify complex UK areas
update my_areas s
set geom_27700 = sdo_util.simplify(geom_27700,10)
,   geom = sdo_cs.transform(sdo_util.simplify(geom_27700,10),4326)
,   num_pts = NULL
where geom_27700 IS NOT NULL
--and SDO_UTIL.GETNUMVERTICES(geom_27700) >= 1e5
and num_pts >= 1e5
;

--bring BNG simplifications to WGS84 geom
update my_areas s
set geom = sdo_cs.transform(geom_27700,4326)
,   num_pts = NULL
where geom_27700 IS NOT NULL
and SDO_UTIL.GETNUMVERTICES(geom_27700) < 1e5
and SDO_UTIL.GETNUMVERTICES(geom) >= 1e5
and (num_pts >= 1e5 OR num_pts is null)
;

--simplify non-UK areas 
update my_areas s
set geom = sdo_util.simplify(geom,10)
,   num_pts = NULL
where geom_27700 IS NULL
--and SDO_UTIL.GETNUMVERTICES(geom) >= 1e5
and num_pts >= 1e5
;

update my_areas s
set num_pts = SDO_UTIL.GETNUMVERTICES(geom)
where num_pts IS NULL
and geom is not null
/



with x as (
select area_code, area_number, name, num_pts
, SDO_UTIL.GETNUMVERTICES(geom) num_vert_4326
, SDO_UTIL.GETNUMVERTICES(geom_27700) num_vert_27700
, SDO_UTIL.GETNUMVERTICES(sdo_util.simplify(geom,10)) simp_4326
, SDO_UTIL.GETNUMVERTICES(sdo_util.simplify(geom_27700,10)) simp_27700
from my_areas
)
select x.* from x
where num_vert_4326>1e5 
or    num_vert_27700>1e5 
or    num_vert_4326 != num_vert_27700
or    num_pts > 1e5
order by num_vert_4326 desc
/

/*
AREA AREA_NUMBER NAME                                                         NUM_VERT_4326 NUM_VERT_27700
---- ----------- ------------------------------------------------------------ ------------- --------------
UTA       131955 Shetland Islands                                                    197930         197930
CCTY          66 Ross and Cromarty                                                   172725         172725
CCTY          61 Orkney                                                              164010         164010
UTA       129557 Orkney Islands                                                      161272         161272
AONB          18 South Devon                                                         119343         119343
UTW       128174 Wester Ross, Strathpeffer and Lochalsh                              111196         111196
UTA       122011 Cornwall                                                            110206         110206
UTW       131978 Beinn na Foghla agus Uibhist a Tuath                                109908         109908
UTW       130079 Kintyre and the Islands                                             104391         104391
UTW       128176 North, West and Central Sutherland                                  100430         100430
UTA       129866 Highland                                                             67438         381605
CCTY          87 Western Isles                                                        63920         328198
UTA       136431 Na h-Eileanan an Iar                                                 62055         328551
UTA       127078 Argyll and Bute                                                      52322         301853
*/
