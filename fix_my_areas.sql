REM fix_my_areas.sql
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
--identify children with same name - no point adding them to activity_areas, but need to drill into their children
alter table my_areas2 modify matchable default 1;
update my_areas2
set matchable=1;

update my_areas2 u 
SET u.matchable = 0
where (area_code, area_number) IN(
select /*p.area_code parent_area_code, p.area_number parent_area_number 
, p.name parent_name, p.num_children, sdo_geom.sdo_area(p.geom, unit=>'unit=SQ_KM') p_area,*/
 c.area_code, c.area_number /*, sdo_geom.sdo_area(c.geom, unit=>'unit=SQ_KM') c_Area*/
from my_areas2 p, my_areas2 c
where p.area_code = c.parent_area_code
and p.area_number = c.parent_area_number
and p.name = c.name
) 
/
----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
--exec dbms_stats.gather_table_stats(user,'MY_AREAS2');
update my_Areas2 p
set p.num_children = (select NULLIF(count(*),0)
  from my_Areas2 c
  where c.parent_area_Code = p.area_Code
  and   c.parent_area_number = p.area_number
  and   c.parent_uqid = p.uqid)
/

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
and num_pts>300*distance_km
/

column activity_name format a40
column ppkm format 9999
select activity_id, activity_date, activity_name, distance_km, num_pts, num_pts/distance_km ppkm, power(num_pts,2)/power(distance_km,3) q
, sdo_geom.sdo_length(geom, unit=>'unit=km')  calc_km
, sdo_util.getnumvertices(geom) actual_pts
, sdo_util.getnumvertices(sdo_util.simplify(geom,1)) simp_pts
from activities
where num_pts > 1000
and num_pts>300*distance_km
order by q
/



----------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------
--simplifying the western isles to reduce number of points before conversion to 4326
update my_Areas2 s
set geom_27700 = sdo_util.simplify(geom_27700,10)
--,   geom_27700 = sdo_util.simplify(geom_27700,10)
where geom_27700 IS NOT NULL
and SDO_UTIL.GETNUMVERTICES(geom_27700) >= 150000
;
update my_Areas2 s
set geom = sdo_cs.transform(geom_27700,4326)
where geom_27700 IS NOT NULL
and SDO_UTIL.GETNUMVERTICES(geom_27700) < 150000
and SDO_UTIL.GETNUMVERTICES(geom) >= 150000
;

with x as (
select area_code, area_number, name
, SDO_UTIL.GETNUMVERTICES(geom) num_vert_4326
, SDO_UTIL.GETNUMVERTICES(geom_27700) num_vert_27700
--, SDO_UTIL.GETNUMVERTICES(sdo_util.simplify(geom_27700,10))
from my_Areas2
)
select x.* from x
where num_vert_4326>1e5 
or    num_vert_27700>1e5 
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

AREA AREA_NUMBER NAME                                                         NUM_VERT_4326 NUM_VERT_27700
---- ----------- ------------------------------------------------------------ ------------- --------------
UTA       129866 Highland                                                             67438         381605
CCTY          87 Western Isles                                                        63920         328198
UTA       136431 Na h-Eileanan an Iar                                                 62055         328551
UTA       127078 Argyll and Bute                                                      52322         301853
*/
