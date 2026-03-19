REM ireland_settlement_townloads.sql

----------------------------------------------------------------------------------------------------
-- verify area match 
-- see https://docs.oracle.com/database/121/SPATL/spatial-relationships-and-filtering.htm#SPATL460
----------------------------------------------------------------------------------------------------
with x as (
select /*+MATERIALIZE*/
       p.area_code p_area_code, p.area_number p_area_number, p.name p_name
,      s.area_code s_area_code, s.area_number s_area_number, s.name s_name
,      t.area_code t_area_code, t.area_number t_area_number, t.name t_name
,      sdo_relate(t.geom,s.geom,'OVERLAPBDYINTERSECT') overlapping
,      sdo_relate(t.geom,s.geom,'COVEREDBY+INSIDE') coveredby
,      sdo_relate(t.geom,s.geom,'COVERS+CONTAINS') inside
,      round(sdo_geom.sdo_area(s.geom, unit=>'unit=sq_km'),3) settlement_km_sq
,      round(sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km'),3) town_km_sq
,      round(sdo_geom.sdo_area(sdo_geom.sdo_intersection(t.geom,s.geom,1), unit=>'unit=sq_km'),3) intersect_km_sq    
from   my_areas t, my_areas s, my_areas p
where  t.area_code = 'TOWN'
and    s.area_code = 'SETL'
and    t.parent_area_code = 'CTY' --currently matched to county
and    p.area_code = t.parent_area_code
and    p.area_number = t.parent_area_number
and    t.parent_area_code = s.parent_area_code
and    t.parent_area_number = s.parent_area_number
and    SDO_ANYINTERACT(t.geom, s.geom)
and    SDO_ANYINTERACT(t.mbr, s.mbr) 
and    s.matchable = 1
and    t.matchable = 1
--and    t.name like 'Powerscourt%'
--and    p.name = 'Wicklow'
--and    t.name like s.name||' %'
), y as (
select x.*
, round(100*intersect_km_sq/least(settlement_km_sq,town_km_sq),2) pct
from X 
)
select * from y
where pct >= 95
fetch first 10 rows only
/

----------------------------------------------------------------------------------------------------
-- alter town parents to match enclosing parents
----------------------------------------------------------------------------------------------------
clear screen
set serveroutput on timi on
DECLARE
  l_intersection_pct NUMBER := 98;
  l_intersection_abs NUMBER := 0.025;
  l_intersection_diff_of_parent_pct NUMBER := 2;
BEGIN
  FOR i IN (
    with x as (
    select /*+MATERIALIZE*/
           p.area_code p_area_code, p.area_number p_area_number, p.name p_name
    ,      s.area_code s_area_code, s.area_number s_area_number, s.uqid s_uqid, s.name s_name
    ,      t.area_code t_area_code, t.area_number t_area_number, t.uqid t_uqid, t.name t_name
    ,      sdo_relate(t.geom,s.geom,'OVERLAPBDYINTERSECT') overlapping
    ,      sdo_relate(t.geom,s.geom,'COVEREDBY+INSIDE') coveredby
    ,      sdo_relate(t.geom,s.geom,'COVERS+CONTAINS') inside
    ,      sdo_geom.sdo_area(s.geom, unit=>'unit=sq_km') s_kmsq
    ,      sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km') t_kmsq
    ,      sdo_geom.sdo_area(sdo_geom.sdo_intersection(t.geom,s.geom,1), unit=>'unit=sq_km') i_kmsq
    from   my_areas t, my_areas s, my_areas p
    where  t.area_code = 'TOWN'
    and    s.area_code = 'SETL'
	and    t.parent_area_code = 'CTY' --currently matched to county
	--and    t.parent_area_number = 250000 --Wicklow
	--and    t.parent_area_number = 260000 --Dublin
    and    p.area_code = t.parent_area_code /*share same parent*/
    and    p.area_number = t.parent_area_number
    and    t.parent_area_code = s.parent_area_code
    and    t.parent_area_number = s.parent_area_number
    and    SDO_ANYINTERACT(t.geom, s.geom)
    and    SDO_ANYINTERACT(t.mbr, s.mbr) 
	and    t.name like s.name||' %'
    ), y as (
    select x.*
    , 100*i_kmsq/least(s_kmsq,t_kmsq) pct
    from X 
    )
    select * from y
    where pct >= l_intersection_pct -5
	--FETCH FIRST 1000 ROWS ONLY
  ) LOOP
    IF i.coveredby OR (i.s_kmsq > i.t_kmsq AND i.pct >= l_intersection_pct) 
	               OR (i.t_kmsq-i.i_kmsq < l_intersection_abs)
				   OR (100*(i.t_kmsq-i.i_kmsq)/i.s_kmsq < l_intersection_diff_of_parent_pct AND i.t_name=i.s_name) THEN
      dbms_output.put_line(i.t_area_code||'-'||i.t_area_number||'-'||i.t_name||'('||ROUND(i.t_kmsq,3)||' Km^2) is covered by '
	                     ||i.s_area_code||'-'||i.s_area_number||'-'||i.s_name||'('||ROUND(i.s_kmsq,3)||' Km^2).  Intersection:'
						 ||ROUND(i.i_kmsq,3)||' Km^2 ('||ROUND(i.pct,3)||'%)'
					     );
      UPDATE my_areas
	  SET   parent_area_code = i.s_area_code
	  ,     parent_area_number = i.s_area_number
	  ,     parent_uqid = i.s_uqid
	  ,     matchable = 0
	  WHERE area_code = i.t_area_code
	  AND   area_number = i.t_area_number;
      COMMIT;

	ELSIF i.inside OR (i.t_kmsq > i.s_kmsq AND i.pct >= l_intersection_pct) 
	               OR (i.s_kmsq-i.i_kmsq < l_intersection_abs)
				   OR (100*(i.s_kmsq-i.i_kmsq)/i.t_kmsq < l_intersection_diff_of_parent_pct AND i.t_name=i.s_name) THEN 
      dbms_output.put_line(i.t_area_code||'-'||i.t_area_number||'-'||i.t_name||'('||ROUND(i.t_kmsq,3)||' Km^2) contains '
	                     ||i.s_area_code||'-'||i.s_area_number||'-'||i.s_name||'('||ROUND(i.s_kmsq,3)||' Km^2).  Intersection:'
						 ||ROUND(i.i_kmsq,3)||' Km^2 ('||ROUND(i.pct,3)||'%)'
					     );
      UPDATE my_areas
	  SET   parent_area_code = i.t_area_code
	  ,     parent_area_number = i.t_area_number
	  ,     parent_uqid = i.t_uqid
	  ,     matchable = 0
	  WHERE area_code = i.s_area_code
	  AND   area_number = i.s_area_number;
      COMMIT;

	ELSE 
      dbms_output.put_line(i.t_area_code||'-'||i.t_area_number||'-'||i.t_name||'('||ROUND(i.t_kmsq,3)||' Km^2) intersects '
	                     ||i.s_area_code||'-'||i.s_area_number||'-'||i.s_name||'('||ROUND(i.s_kmsq,3)||' Km^2).  Intersection:'
						 ||ROUND(i.i_kmsq,3)||' Km^2 ('||ROUND(i.pct,3)||'%)'
					     );
	END IF;
  END LOOP;
END;
/
----------------------------------------------------------------------------------------------------
--make child of town/settlement non-matchable
----------------------------------------------------------------------------------------------------
/*--one time fix, now done in match above--
UPDATE my_areas
SET    matchable = 0
WHERE  matchable = 1
AND    uqid LIKE 'IRL%'
AND    area_code IN('TOWN','SETL')
AND    parent_area_code IN('TOWN','SETL')
*/
----------------------------------------------------------------------------------------------------
--list numbers of town/settlement/county/province combinations
----------------------------------------------------------------------------------------------------
select area_code, parent_area_code, matchable, count(*)
from my_areas
where area_code IN('SETL','TOWN')
and uqid like 'IRL%'
group by area_code, parent_area_code, matchable
/

----------------------------------------------------------------------------------------------------
--list related town/settlements by parent
----------------------------------------------------------------------------------------------------
select c.parent_area_code, c.parent_area_number, p.name, p.matchable
,      c.area_code, c.area_number, c.name, c.matchable
,      sdo_geom.sdo_area(c.geom, unit=>'unit=sq_km') area
from my_areas p, my_areas c
where 1=1
and p.area_code = c.parent_area_code
and p.area_number = c.parent_area_number
and c.area_code IN('TOWN','SETL')
and c.parent_area_code IN('TOWN','SETL')
and p.name like 'Dublin%'
order by c.parent_area_code, p.name, p.area_number
, area desc 
--, c.area_code, c.name, c.area_number
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
--overide matchability on children
----------------------------------------------------------------------------------------------------
UPDATE my_areas
SET matchable = 1
where matchable = 0
AND area_code = 'TOWN'
and parent_area_code = 'SETL'
and area_number IN(
  260358 --Dun Laoghaire
 ,260322 --Dalkey
 );
UPDATE my_areas
SET matchable = 0
where matchable = 1
AND area_code = 'TOWN'
and parent_area_code = 'SETL'
and area_number IN(
  260356 --Dundrum
 );
----------------------------------------------------------------------------------------------------
--mark for recalculation of area list - optional
----------------------------------------------------------------------------------------------------
MERGE INTO activities u
USING (
select a.activity_id, a.name, a.start_date_utc, a.processing_status, a.last_updated act_last_updated
, MAX(ma.last_updated) areas_last_updated
from activities a
,    activity_areas aa
,    my_areas ma
where a.activity_id = aa.activity_id
and ma.area_code =aa.area_code 
and ma.area_number = aa.area_number
and a.last_updated < ma.last_updated
and a.processing_status >4
group by a.activity_id, a.name, a.start_date_utc, a.processing_status, a.last_updated
) s
ON (s.activity_id = u.activity_id)
WHEN MATCHED THEN UPDATE
SET u.processing_status = 4
/


