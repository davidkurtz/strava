REM ireland_townlands_simplify.sql

----------------------------------------------------------------------------------------------------
-- add a user defined area to hold combined touching townloads with the same main name
----------------------------------------------------------------------------------------------------
insert into my_area_codes
select 'UCTL', 'User Combined Townlands', area_level
from my_area_codes
where area_Code = 'TOWN'
/

----------------------------------------------------------------------------------------------------
--create a backup of the my_areas table
----------------------------------------------------------------------------------------------------
create table backup_my_areas as select * from my_areas;

----------------------------------------------------------------------------------------------------
--function to trim frequent Irish townland name suffixes
----------------------------------------------------------------------------------------------------
create or replace function strava.townland_trim_suffix
(p_name VARCHAR2)
RETURN VARCHAR2 IS 
  l_name VARCHAR2(1000 CHAR);
  l_other_words VARCHAR2(100 CHAR);
  l_last_word VARCHAR2(100 CHAR);
  l_counter INTEGER := 0;
BEGIN
  --remove trailing brackets
  l_name := REGEXP_REPLACE(p_name, '\s*\([^)]*\)\s*$', '');
  
  WHILE l_counter < 2 LOOP
    l_counter := l_counter + 1;
    l_last_word := REGEXP_SUBSTR(l_name, '[^[:space:]]+$');
    l_other_words := REGEXP_REPLACE(l_name, '\s+[^[:space:]]+$', '');
    --dbms_output.put_line(l_counter||':'||l_other_words||'~'||l_last_word);
	IF l_last_word IN('Upper','Lower','Middle'
	                 ,'North','South','East','West'
					 ,'Big','Great','Little','Beg','More'
					 ,'Demesne','Deerpark','Paddock','Mountain','Domain','Commons'
					 ) THEN
      l_name := l_other_words;
	ELSE 
	  EXIT;
	END IF;
  END LOOP;
  return l_name;
END;
/

select area_code, area_number, name, parent_area_code, parent_area_number, townland_trim_suffix(name)
from my_areas
where 1=1
--and area_code = 'TOWN'
and name like 'Ballyduhig%'
--and name like '%(%)%'
order by 1
/

select s.area_code, s.area_number, s.name
,      t.area_code, t.area_number, t.name
,      sdo_geom.relate(s.geom,'DETERMINE',t.geom,1)
from my_areas s, my_areas t
where s.area_number < t.area_number
and s.parent_area_code = t.parent_area_code
and s.parent_area_number = t.parent_area_number
and s.name like 'Farranarouga%'
and t.name like 'Farranarouga%'
/

----------------------------------------------------------------------------------------------------
--first pass to join 2 adjacent townlands with the same leading name
----------------------------------------------------------------------------------------------------
--rollback;
clear screen
set echo on serveroutput on 
DECLARE --first pass:two townlands where there is no UCTL
  l_union_geom MDSYS.SDO_GEOMETRY;
  l_union_area_code   my_areas.area_code%TYPE;
  l_union_area_number my_areas.area_number%TYPE;
  l_union_area_level  my_areas.area_level%TYPE;
  
  l_s_parent_area_code   my_areas.parent_area_code%TYPE;
  l_s_parent_area_number my_areas.parent_area_number%TYPE;

  l_t_parent_area_code   my_areas.parent_area_code%TYPE;
  l_t_parent_area_number my_areas.parent_area_number%TYPE;
BEGIN 
  FOR i IN (
    with x as (
    select /*MATERIALIZE*/
         p.area_code p_area_code, p.area_number p_area_number, p.name p_name, p.geom p_geom
,        strava.townland_trim_suffix(s.name) s_other_words
--,        REGEXP_SUBSTR(s.name, '[^[:space:]]+$') s_last_word
,        s.area_code s_area_code, s.area_number s_area_number, s.area_level s_area_level, s.name s_name, s.geom s_geom
,        t.area_code t_area_code, t.area_number t_area_number, t.area_level t_area_level, t.name t_name, t.geom t_geom
,        strava.townland_trim_suffix(t.name) t_other_words
,        sdo_geom.relate(s.geom,'TOUCH',t.geom,1) touching
--,        round(sdo_geom.sdo_area(s.geom, unit=>'unit=sq_km'),3) settlement_km_sq
--,        round(sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km'),3) town_km_sq
--,        round(sdo_geom.sdo_area(sdo_geom.sdo_intersection(t.geom,s.geom,1), unit=>'unit=sq_km'),3) intersect_km_sq    
    from   my_areas t, my_areas s, my_areas p
    where  t.area_code IN('TOWN')
    and    s.area_code IN('TOWN')
    and    p.area_code = 'CTY' --children of county
    --and    p.area_number = 40000 --qwert
    --and    s.name like 'Farranarouga%'
    --and    p.parent_area_code = 'PROV'
	--and    p.parent_area_number IN(27001,27002,27003,27004)
    --and    p.area_number = 35001 --qwert
	--and    p.area_code = 'SETL' --children of county
    and    p.area_code = s.parent_area_code
    and    p.area_number = s.parent_area_number
    and    p.area_code = t.parent_area_code
    and    p.area_number = t.parent_area_number
    and    t.parent_area_code = s.parent_area_code --sibling
    and    t.parent_area_number = s.parent_area_number --sibling
    and    s.area_number < t.area_number --not the same area twice
    and    sdo_geom.relate(s.geom,'TOUCH',t.geom,1) = 'TOUCH'
    and    SDO_ANYINTERACT(t.geom, s.geom)
    and    SDO_ANYINTERACT(t.mbr, s.mbr) 
	)
	select * from x
	where s_other_words = t_other_words
    --and    s_name like 'Ballinvally%' --'Kilruddery%'
    --and    t_name like 'Ballinvally%' --'Kilruddery%'
    --and    p_name = 'Wicklow'
	ORDER BY s_area_number, t_area_number
	FETCH FIRST 50 ROWS ONLY
  ) LOOP
    dbms_output.put_line('Considering '||i.s_area_code||'-'||i.s_area_number||':'||i.s_name
	                          ||' -v- '||i.t_area_code||'-'||i.t_area_number||':'||i.t_name);


    SELECT a.parent_area_code, a.parent_area_number
	INTO   l_s_parent_area_code, l_s_parent_area_number
	FROM   my_areas a
	WHERE  area_code = i.s_area_code
	AND    area_number = i.s_area_number;

    SELECT a.parent_area_code, a.parent_area_number
	INTO   l_t_parent_area_code, l_t_parent_area_number
	FROM   my_areas a
	WHERE  area_code = i.t_area_code
	AND    area_number = i.t_area_number;

    IF l_union_area_code = l_s_parent_area_code AND l_union_area_number = l_s_parent_area_number THEN
	  l_union_geom := sdo_geom.sdo_union(l_union_geom, i.t_geom);
	ELSIF l_union_area_code = l_t_parent_area_code AND l_union_area_number = l_t_parent_area_number THEN
	  l_union_geom := sdo_geom.sdo_union(l_union_geom, i.s_geom);
	ELSE 
      l_union_geom := sdo_geom.sdo_union(i.s_geom, i.t_geom);
	  l_union_area_code := 'UCTL';
	  l_union_area_number := LEAST(i.s_area_number,i.t_area_number);
	  l_union_area_level := LEAST(i.s_area_level,i.t_area_level);
	END IF;

    IF l_union_area_number > 0 THEN
      BEGIN --insert/update union area
	    dbms_output.put_line('Insert '||l_union_area_code||'-'||l_union_area_number||':'||i.s_other_words);
	    INSERT INTO my_areas
	    (area_code, area_number, area_level, name, geom, mbr, num_pts
	    ,parent_area_code, parent_area_number)
	    VALUES
	    (l_union_area_code, l_union_area_number
		, l_union_area_level, i.s_other_words, l_union_geom
	    ,sdo_geom.sdo_mbr(l_union_geom), SDO_UTIL.GETNUMVERTICES(l_union_geom)
 	    ,i.p_area_code, i.p_area_number);
	  EXCEPTION
	    WHEN dup_val_on_index THEN
   	      dbms_output.put_line('Update already inserted area '||l_union_area_code||'-'||l_union_area_number||':'||i.s_other_words);
		  UPDATE my_areas
		  SET    geom = l_union_geom
		  ,      mbr = sdo_geom.sdo_mbr(l_union_geom)
		  ,      num_pts = SDO_UTIL.GETNUMVERTICES(l_union_geom)
		  WHERE  area_code = l_union_area_code
		  AND    area_number = l_union_area_number;
	  END;

      dbms_output.put_line('Update parent of '||i.s_area_code||'-'||i.s_area_number||':'||i.s_name);
	  UPDATE my_areas
	  SET    parent_area_code = l_union_area_code
	  ,      parent_area_number = l_union_area_number
	  ,      matchable = 0
	  ,	     name_hierarchy = ''
	  WHERE  area_code = i.s_area_code
	  AND    area_number = i.s_area_number;

      dbms_output.put_line('Update parent of '||i.t_area_code||'-'||i.t_area_number||':'||i.t_name);
      UPDATE my_areas
	  SET    parent_area_code = l_union_area_code
	  ,      parent_area_number = l_union_area_number
	  ,      matchable = 0
	  ,     name_hierarchy = ''
	  WHERE  area_code = i.t_area_code
	  AND    area_number = i.t_area_number;

	END IF;
  END LOOP;	
END;
/

----------------------------------------------------------------------------------------------------
--second pass - merge interacting sibling UCTL areas with same name
----------------------------------------------------------------------------------------------------
clear screen
set echo on serveroutput on 
DECLARE 
  l_union_geom MDSYS.SDO_GEOMETRY;
  l_union_area_code   my_areas.area_code%TYPE;
  l_union_area_number my_areas.area_number%TYPE;
  l_union_area_level  my_areas.area_level%TYPE;
  l_delete_area_number my_areas.area_number%TYPE;
  
  l_s_area_code   my_areas.parent_area_code%TYPE;
  l_s_area_number my_areas.parent_area_number%TYPE;

  l_t_area_code   my_areas.parent_area_code%TYPE;
  l_t_area_number my_areas.parent_area_number%TYPE;
BEGIN 
  FOR i IN (
    with x as (
    select /*MATERIALIZE*/
         p.area_code p_area_code, p.area_number p_area_number, p.name p_name, p.geom p_geom
,        strava.townland_trim_suffix(s.name) s_other_words
--,        REGEXP_SUBSTR(s.name, '[^[:space:]]+$') s_last_word
,        s.area_code s_area_code, s.area_number s_area_number, s.area_level s_area_level, s.name s_name, s.geom s_geom
,        t.area_code t_area_code, t.area_number t_area_number, t.area_level t_area_level, t.name t_name, t.geom t_geom
,        strava.townland_trim_suffix(t.name) t_other_words
,        sdo_geom.relate(s.geom,'TOUCH',t.geom,1) touching
,        sdo_geom.relate(s.geom,'OVERLAPBDYINTERSECT',t.geom,1) overlapping
--,        round(sdo_geom.sdo_area(s.geom, unit=>'unit=sq_km'),3) settlement_km_sq
--,        round(sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km'),3) town_km_sq
--,        round(sdo_geom.sdo_area(sdo_geom.sdo_intersection(t.geom,s.geom,1), unit=>'unit=sq_km'),3) intersect_km_sq    
    from   my_areas t, my_areas s, my_areas p
    where  t.area_code IN('UCTL')
    and    s.area_code IN('UCTL')
    --and    p.area_code = 'CTY' --children of county
	--and    p.parent_area_code = 'PROV'
	--and    p.parent_area_number IN(27001,27002,27003,27004)
    --and    p.area_code = 'SETL' --children of county
	--and    p.parent_area_number IN(35001)
    and    p.area_code = s.parent_area_code
    and    p.area_number = s.parent_area_number
    and    p.area_code = t.parent_area_code
    and    p.area_number = t.parent_area_number
    and    t.parent_area_code = s.parent_area_code --sibling
    and    t.parent_area_number = s.parent_area_number --sibling
    and    s.area_number < t.area_number --not the same area twice
	and    s.name = t.name
    --and    sdo_geom.relate(s.geom,'TOUCH',t.geom,1) = 'TOUCH'
    and    SDO_ANYINTERACT(t.geom, s.geom)
    and    SDO_ANYINTERACT(t.mbr, s.mbr) 
	)
	select * from x
	ORDER BY s_area_number, t_area_number
	--FETCH FIRST 50 ROWS ONLY
  ) LOOP
    dbms_output.put_line('Considering '||i.s_area_code||'-'||i.s_area_number||':'||i.s_name
	                          ||' -v- '||i.t_area_code||'-'||i.t_area_number||':'||i.t_name);

    BEGIN 
      SELECT a.parent_area_code, a.parent_area_number
	  INTO   l_s_area_code, l_s_area_number
	  FROM   my_areas a
	  WHERE  area_code = i.s_area_code
	  AND    area_number = i.s_area_number;
	EXCEPTION
	  WHEN no_data_found THEN
	     l_s_area_code := NULL;
		 l_s_area_number := NULL;
    END;
	
	BEGIN
      SELECT a.parent_area_code, a.parent_area_number
	  INTO   l_t_area_code, l_t_area_number
	  FROM   my_areas a
	  WHERE  area_code = i.t_area_code
	  AND    area_number = i.t_area_number;
	EXCEPTION
	  WHEN no_data_found THEN
	     l_t_area_code := NULL;
		 l_t_area_number := NULL;
    END;
	
    IF l_union_area_code = l_s_area_code AND l_union_area_number = l_s_area_number AND l_t_area_number IS NOT NULL THEN
	  l_union_geom := sdo_geom.sdo_union(l_union_geom, i.t_geom);
	ELSIF l_union_area_code = l_t_area_code AND l_union_area_number = l_t_area_number AND l_s_area_number IS NOT NULL THEN
	  l_union_geom := sdo_geom.sdo_union(l_union_geom, i.s_geom);
	ELSIF l_t_area_number IS NOT NULL and l_s_area_number IS NOT NULL THEN 
      l_union_geom := sdo_geom.sdo_union(i.s_geom, i.t_geom);
	  l_union_area_code := 'UCTL';
	  l_union_area_number := LEAST(i.s_area_number,i.t_area_number);
	  l_union_area_level := LEAST(i.s_area_level,i.t_area_level);
	  l_delete_area_number := GREATEST(i.s_area_number,i.t_area_number);
	ELSE
	  l_union_area_number := NULL;
	  l_delete_area_number := NULL;
	END IF;

    IF l_union_area_number > 0 THEN
      BEGIN --insert/update union area
	    dbms_output.put_line('Insert '||l_union_area_code||'-'||l_union_area_number||':'||i.s_other_words);
	    INSERT INTO my_areas
	    (area_code, area_number, area_level, name, geom, mbr, num_pts
	    ,parent_area_code, parent_area_number)
	    VALUES
	    (l_union_area_code, l_union_area_number
		, l_union_area_level, i.s_other_words, l_union_geom
	    ,sdo_geom.sdo_mbr(l_union_geom), SDO_UTIL.GETNUMVERTICES(l_union_geom)
 	    ,i.p_area_code, i.p_area_number);
	  EXCEPTION
	    WHEN dup_val_on_index THEN
   	      dbms_output.put_line('Update already inserted area '||l_union_area_code||'-'||l_union_area_number||':'||i.s_other_words);
		  UPDATE my_areas
		  SET    geom = l_union_geom
		  ,      mbr = sdo_geom.sdo_mbr(l_union_geom)
		  ,      num_pts = SDO_UTIL.GETNUMVERTICES(l_union_geom)
		  WHERE  area_code = l_union_area_code
		  AND    area_number = l_union_area_number;
	  END;

      IF l_delete_area_number > 0 THEN
        dbms_output.put_line('Update children of '||l_union_area_code||'-'||l_delete_area_number);
	    UPDATE my_areas
	    SET    parent_area_code = l_union_area_code
	    ,      parent_area_number = l_union_area_number
	    ,      matchable = 0
	    ,	     name_hierarchy = ''
	    WHERE  parent_area_code = l_union_area_code
	    AND    parent_area_number = l_delete_area_number;

        dbms_output.put_line('Delete '||l_union_area_code||'-'||l_delete_area_number);
        DELETE FROM my_areas
	    WHERE  area_code = l_union_area_code
	    AND    area_number = l_delete_area_number;
      END IF;
	END IF;
  END LOOP;	
END;
/

----------------------------------------------------------------------------------------------------
--third pass TOWN -v- UCTL
----------------------------------------------------------------------------------------------------
clear screen
set echo on serveroutput on 
DECLARE 
  l_union_geom MDSYS.SDO_GEOMETRY;
  l_union_area_code   my_areas.area_code%TYPE;
  l_union_area_number my_areas.area_number%TYPE;
  
  l_t_area_code   my_areas.parent_area_code%TYPE;
  l_t_area_number my_areas.parent_area_number%TYPE;
BEGIN 
  FOR i IN (
    with x as (
    select /*MATERIALIZE*/
         p.area_code p_area_code, p.area_number p_area_number, p.name p_name, p.geom p_geom
--,        strava.townland_trim_suffix(u.name) u_other_words
--,        REGEXP_SUBSTR(u.name, '[^[:space:]]+$') u_last_word
,        u.area_code u_area_code, u.area_number u_area_number, u.area_level u_area_level, u.name u_name, u.geom u_geom
,        t.area_code t_area_code, t.area_number t_area_number, t.area_level t_area_level, t.name t_name, t.geom t_geom
,        strava.townland_trim_suffix(t.name) t_other_words
,        sdo_geom.relate(u.geom,'TOUCH',t.geom,1) touching
,        sdo_geom.relate(u.geom,'OVERLAPBDYINTERSECT',t.geom,1) overlapping
--,        round(sdo_geom.sdo_area(u.geom, unit=>'unit=sq_km'),3) settlement_km_sq
--,        round(sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km'),3) town_km_sq
--,        round(sdo_geom.sdo_area(sdo_geom.sdo_intersection(t.geom,u.geom,1), unit=>'unit=sq_km'),3) intersect_km_sq    
    from   my_areas t, my_areas u, my_areas p
    where  t.area_code IN('TOWN')
    and    u.area_code IN('UCTL')
    --and    p.area_code = 'CTY' --children of county
	--and    p.area_number = 250000 --Wicklow
	--and    p.parent_area_code = 'PROV'
	--and    p.parent_area_number IN(27001,27002,27003,27004)
    and    p.area_code = 'SETL' --children of county
	and    p.area_number = 35001 --Wicklow
    and    p.area_code = u.parent_area_code
    and    p.area_number = u.parent_area_number
    and    p.area_code = t.parent_area_code
    and    p.area_number = t.parent_area_number
    and    t.parent_area_code = u.parent_area_code --sibling
    and    t.parent_area_number = u.parent_area_number --sibling
	and    t.name like u.name||' %'
	and    t.name != u.name
    --and    sdo_geom.relate(u.geom,'TOUCH',t.geom,1) = 'TOUCH'
    and    SDO_ANYINTERACT(t.geom, u.geom)
    and    SDO_ANYINTERACT(t.mbr, u.mbr) 
	)
	select * from x
	where t_other_words = u_name
	ORDER BY u_area_number, t_area_number
	FETCH FIRST 10 ROWS ONLY
  ) LOOP
    dbms_output.put_line('Considering '||i.u_area_code||'-'||i.u_area_number||':'||i.u_name
	                          ||' -v- '||i.t_area_code||'-'||i.t_area_number||':'||i.t_name);

	BEGIN
      SELECT a.parent_area_code, a.parent_area_number
	  INTO   l_t_area_code, l_t_area_number
	  FROM   my_areas a
	  WHERE  area_code = i.t_area_code
	  AND    area_number = i.t_area_number;
	EXCEPTION
	  WHEN no_data_found THEN
	     l_t_area_code := NULL;
		 l_t_area_number := NULL;
    END;
	
    IF l_t_area_number IS NOT NULL and i.u_area_number IS NOT NULL THEN 
      l_union_geom := sdo_geom.sdo_union(i.u_geom, i.t_geom);
	  l_union_area_code := i.u_area_code;
	  l_union_area_number := i.u_area_number;
	ELSE
	  l_union_area_number := NULL;
	END IF;

    IF l_union_area_number > 0 THEN
	  dbms_output.put_line('Update already inserted area '||l_union_area_code||'-'||l_union_area_number||':'||i.u_name);
	  UPDATE my_areas
	  SET    geom = l_union_geom
	  ,      mbr = sdo_geom.sdo_mbr(l_union_geom)
	  ,      num_pts = SDO_UTIL.GETNUMVERTICES(l_union_geom)
	  WHERE  area_code = l_union_area_code
	  AND    area_number = l_union_area_number;

      dbms_output.put_line('Update parent of '||i.t_area_code||'-'||i.t_area_number||':'||i.t_name);
      UPDATE my_areas
	  SET    parent_area_code = l_union_area_code
	  ,      parent_area_number = l_union_area_number
	  ,      matchable = 0
	  ,	     name_hierarchy = ''
	  WHERE  area_code = i.t_area_code
	  AND    area_number = i.t_area_number;
	END IF;
  END LOOP;	
END;
/

----------------------------------------------------------------------------------------------------
--list new UCTL areas
----------------------------------------------------------------------------------------------------
select x.*
, sdo_geom.sdo_area(x.geom, unit=>'unit=sq_km')
from my_areas x
where (area_code = 'UCTL' or parent_area_code = 'UCTL')
;

----------------------------------------------------------------------------------------------------
--compare areas of consolidated and consituent areas
----------------------------------------------------------------------------------------------------
with u as (
select /*+MATERIALIZE*/ u.area_code, u.area_number, u.name
, sdo_geom.sdo_area(u.geom, unit=>'unit=sq_km') area_u
from my_areas u
where u.area_code = 'UCTL'
), t as (
select /*+MATERIALIZE*/ t.parent_area_code, t.parent_area_number, count(*) num_areas
, sum(sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km')) area_t
from my_areas t
where t.parent_area_code = 'UCTL'
group by t.parent_area_code, t.parent_area_number
)
select u.*, round(t.area_t,3) area_t
, round(100*u.area_u/t.area_t,3) area_pct
, t.num_areas
from u, t
where u.area_code = t.parent_area_code
and u.area_number = t.parent_area_number
and (u.area_u/t.area_t < 0.999 
  OR u.area_u/t.area_t > 1.001)
order by 1,2,3
/

select area_code, count(*), sum(matchable)
from my_areas
where area_code IN('TOWN','SETL','UCTL')
group by area_code
/
----------------------------------------------------------------------------------------------------
-- insert missing activities of parents 
----------------------------------------------------------------------------------------------------
insert into activity_areas (activity_id, area_code, area_number)
select DISTINCT ca.activity_id, p.area_code, p.area_number
from activity_areas ca
  inner join my_areas c on c.area_code = ca.area_code       AND c.area_number = ca.area_number
  inner join my_areas p on p.area_code = c.parent_area_code AND p.area_number = c.parent_area_number
  inner join activities a on a.activity_id = ca.activity_id
where not exists(
  select 'x' 
  from activity_areas pa
  where pa.activity_id = ca.activity_id
  and   pa.area_code = p.area_Code
  and   pa.area_number = p.area_number)
--and p.area_code = 'UCTL'
--and c.area_code = 'TOWN'
/
----------------------------------------------------------------------------------------------------
-- update null geometry lengths
----------------------------------------------------------------------------------------------------
update activity_areas aa
set aa.geom_length = (
  select sdo_geom.sdo_length(SDO_GEOM.sdo_intersection(m.geom,a.geom,1), unit=>'unit=km')
  from activities a 
    inner join my_areas m on m.area_code = aa.area_code and m.area_number = aa.area_number
  where a.activity_id = aa.activity_id)
where aa.geom_length IS null
and aa.area_code = 'UCTL'
/
----------------------------------------------------------------------------------------------------
--update related geometries
----------------------------------------------------------------------------------------------------
UPDATE my_areas
SET    mbr = sdo_geom.sdo_mbr(geom)
,      num_pts = SDO_UTIL.GETNUMVERTICES(geom)
where  area_code = 'UCTL'
and    (num_pts IS NULL or mbr IS NULL)
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
