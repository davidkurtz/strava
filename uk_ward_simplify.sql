REM uk_ward_simplify.sql

----------------------------------------------------------------------------------------------------
-- add a user defined area to hold combined touching townloads with the same main name
----------------------------------------------------------------------------------------------------
delete from my_area_codes where area_code = 'UCCW';
insert into my_area_codes
select distinct 'UC'||substr(area_code,1,1)||'W', 'User Combined '||description, area_level
from my_area_codes
where area_Code like '__W'
/

----------------------------------------------------------------------------------------------------
--create a backup of the my_areas table
----------------------------------------------------------------------------------------------------
--drop table backup_my_areas purge;
create table backup_my_areas as select * from my_areas
;
select distinct area_code, parent_area_code
from my_areas
where area_Code like '__W'
/
----------------------------------------------------------------------------------------------------
--function to trim frequent UK ward name suffixes
----------------------------------------------------------------------------------------------------
create or replace function strava.uk_trim_suffix
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
	IF l_last_word IN('Upper','Lower','Middle','Central'
	                 ,'North','South','East','West'
                     ,'South-West'
                     ,'Rural','Inferior','Superior'
					 ) THEN
      l_name := l_other_words;
	ELSE 
	  EXIT;
	END IF;
  END LOOP;
  return l_name;
END;
/

with x as (
select c.area_code, c.name, uk_trim_suffix(c.name) trimmed_name, c.num_children, p.name parent_name, p.num_children num_siblings
from my_areas c
  inner join my_areas p on p.area_Code = c.parent_area_Code and p.area_number = c.parent_area_number
where c.area_code LIKE '__W'
)
select x.* from x
where name != trimmed_name
order by 2
/

----------------------------------------------------------------------------------------------------
--first pass to join 2 adjacent wards with the same leading name - __W -v- UC_W
--check there is a sibling with non-trimmable name otherwise combined area equivalent to parent
----------------------------------------------------------------------------------------------------
--rollback;
clear screen
set echo on serveroutput on 
DECLARE --first pass:two wards where there is no UCTL
  l_union_geom MDSYS.SDO_GEOMETRY;
  l_union_area_code   my_areas.area_code%TYPE;
  l_union_area_number my_areas.area_number%TYPE;
  l_union_area_level  my_areas.area_level%TYPE;
  
  l_s_parent_area_code   my_areas.parent_area_code%TYPE;
  l_s_parent_area_number my_areas.parent_area_number%TYPE;
  l_s_parent_uqid        my_areas.parent_uqid%TYPE;

  l_t_parent_area_code   my_areas.parent_area_code%TYPE;
  l_t_parent_area_number my_areas.parent_area_number%TYPE;
  l_t_parent_uqid        my_areas.parent_uqid%TYPE;
BEGIN 
  FOR i IN (
    with x as (
    select /*MATERIALIZE*/
         p.area_code p_area_code, p.area_number p_area_number, p.uqid p_uqid, p.name p_name, p.num_children p_num_children, p.geom p_geom
,        strava.uk_trim_suffix(s.name) s_other_words
--,        REGEXP_SUBSTR(s.name, '[^[:space:]]+$') s_last_word
,        s.area_code s_area_code, s.area_number s_area_number, s.uqid s_uqid, s.area_level s_area_level, s.name s_name, s.geom s_geom
,        t.area_code t_area_code, t.area_number t_area_number, t.uqid t_uqid, t.area_level t_area_level, t.name t_name, t.geom t_geom
,        strava.uk_trim_suffix(t.name) t_other_words
,        sdo_geom.relate(s.geom,'TOUCH',t.geom,1) touching
--,        round(sdo_geom.sdo_area(s.geom, unit=>'unit=sq_km'),3) settlement_km_sq
--,        round(sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km'),3) town_km_sq
--,        round(sdo_geom.sdo_area(sdo_geom.sdo_intersection(t.geom,s.geom,1), unit=>'unit=sq_km'),3) intersect_km_sq    
    from   my_areas t, my_areas s, my_areas p
    where  t.area_code LIKE '__W'
	and    t.area_code = s.area_code
	and    p.num_children > 2
    and    p.area_code = s.parent_area_code
    and    p.area_number = s.parent_area_number
    and    p.area_code = t.parent_area_code
    and    p.area_number = t.parent_area_number
    and    t.parent_area_code = s.parent_area_code --sibling
    and    t.parent_area_number = s.parent_area_number --sibling
    and    s.area_number < t.area_number --not the same area twice
    and    sdo_geom.relate(s.geom,'TOUCH',t.geom,1) = 'TOUCH'
    --and    SDO_ANYINTERACT(t.geom, s.geom)
    and    SDO_ANYINTERACT(t.mbr, s.mbr) 
	)
	select * from x
	where s_other_words = t_other_words
	and exists ( --sibling area with a diffrent name
	  select 'x' FROM my_areas y
	  WHERE y.parent_Area_code = x.p_area_Code
	  AND   y.parent_area_number = x.p_area_number
	  AND NOT y.name LIKE s_other_words||'%')
	ORDER BY s_area_number, t_area_number
	FETCH FIRST 500 ROWS ONLY
  ) LOOP
    dbms_output.put_line('Considering '||i.s_area_code||'-'||i.s_area_number||':'||i.s_name
	                          ||' -v- '||i.t_area_code||'-'||i.t_area_number||':'||i.t_name);


    SELECT a.parent_area_code, a.parent_area_number, a.parent_uqid
	INTO   l_s_parent_area_code, l_s_parent_area_number, l_s_parent_uqid
	FROM   my_areas a
	WHERE  area_code = i.s_area_code
	AND    area_number = i.s_area_number;

    SELECT a.parent_area_code, a.parent_area_number, a.parent_uqid
	INTO   l_t_parent_area_code, l_t_parent_area_number, l_t_parent_uqid
	FROM   my_areas a
	WHERE  area_code = i.t_area_code
	AND    area_number = i.t_area_number;

    IF l_union_area_code = l_s_parent_area_code AND l_union_area_number = l_s_parent_area_number THEN
	  l_union_geom := sdo_geom.sdo_union(l_union_geom, i.t_geom);
	ELSIF l_union_area_code = l_t_parent_area_code AND l_union_area_number = l_t_parent_area_number THEN
	  l_union_geom := sdo_geom.sdo_union(l_union_geom, i.s_geom);
	ELSE 
      l_union_geom := sdo_geom.sdo_union(i.s_geom, i.t_geom);
	  l_union_area_code := 'UC'||substr(i.s_area_code,1,1)||'W';
	  l_union_area_number := LEAST(i.s_area_number,i.t_area_number);
	  l_union_area_level := LEAST(i.s_area_level,i.t_area_level);
	END IF;

    IF l_union_area_number > 0 THEN
      BEGIN --insert/update union area
	    dbms_output.put_line('Insert '||l_union_area_code||'-'||l_union_area_number||':'||i.s_other_words);
	    INSERT INTO my_areas
	    (area_code, area_number, uqid, area_level, name, geom, mbr, num_pts
	    ,parent_area_code, parent_area_number, parent_uqid)
	    VALUES
	    (l_union_area_code, l_union_area_number, l_union_area_code||l_union_area_number
		, l_union_area_level, i.s_other_words, l_union_geom
	    ,sdo_geom.sdo_mbr(l_union_geom), SDO_UTIL.GETNUMVERTICES(l_union_geom)
 	    ,i.p_area_code, i.p_area_number, i.p_uqid);
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
	  ,      parent_uqid = l_union_area_code||l_union_area_number
	  ,      matchable = 0
	  ,	     name_hierarchy = ''
	  WHERE  area_code = i.s_area_code
	  AND    area_number = i.s_area_number;

      dbms_output.put_line('Update parent of '||i.t_area_code||'-'||i.t_area_number||':'||i.t_name);
      UPDATE my_areas
	  SET    parent_area_code = l_union_area_code
	  ,      parent_area_number = l_union_area_number
	  ,      parent_uqid = l_union_area_code||l_union_area_number
	  ,      matchable = 0
	  ,     name_hierarchy = ''
	  WHERE  area_code = i.t_area_code
	  AND    area_number = i.t_area_number;

	END IF;
  END LOOP;	
END;
/

----------------------------------------------------------------------------------------------------
--second pass - merge interacting sibling UC_W areas with same name
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
  l_s_uqid        my_areas.parent_uqid%TYPE;

  l_t_area_code   my_areas.parent_area_code%TYPE;
  l_t_area_number my_areas.parent_area_number%TYPE;
  l_t_uqid        my_areas.parent_uqid%TYPE;
BEGIN 
  FOR i IN (
    with x as (
    select /*MATERIALIZE*/
         p.area_code p_area_code, p.area_number p_area_number, p.uqid p_uqid, p.name p_name, p.geom p_geom
,        strava.uk_trim_suffix(s.name) s_other_words
--,        REGEXP_SUBSTR(s.name, '[^[:space:]]+$') s_last_word
,        s.area_code s_area_code, s.area_number s_area_number, s.uqid s_uqid, s.area_level s_area_level, s.name s_name, s.geom s_geom
,        t.area_code t_area_code, t.area_number t_area_number, t.uqid t_uqid, t.area_level t_area_level, t.name t_name, t.geom t_geom
,        strava.uk_trim_suffix(t.name) t_other_words
,        sdo_geom.relate(s.geom,'TOUCH',t.geom,1) touching
,        sdo_geom.relate(s.geom,'OVERLAPBDYINTERSECT',t.geom,1) overlapping
--,        round(sdo_geom.sdo_area(s.geom, unit=>'unit=sq_km'),3) settlement_km_sq
--,        round(sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km'),3) town_km_sq
--,        round(sdo_geom.sdo_area(sdo_geom.sdo_intersection(t.geom,s.geom,1), unit=>'unit=sq_km'),3) intersect_km_sq    
    from   my_areas t, my_areas s, my_areas p
    where  t.area_code LIKE 'UC_W'
    and    s.area_code = t.area_code
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
	  l_union_area_code := i.s_area_code;
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
	    (area_code, area_number, uqid, area_level, name, geom, mbr, num_pts
	    ,parent_area_code, parent_area_number, parent_uqid)
	    VALUES
	    (l_union_area_code, l_union_area_number, l_union_area_code||l_union_area_number
		, l_union_area_level, i.s_other_words, l_union_geom
	    ,sdo_geom.sdo_mbr(l_union_geom), SDO_UTIL.GETNUMVERTICES(l_union_geom)
 	    ,i.p_area_code, i.p_area_number, i.p_uqid);
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
	    ,      parent_uqid = l_union_area_code||l_union_area_number
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
--third pass __W -v- UC_W
----------------------------------------------------------------------------------------------------
clear screen
set echo on serveroutput on 
DECLARE 
  l_union_geom MDSYS.SDO_GEOMETRY;
  l_union_area_code   my_areas.area_code%TYPE;
  l_union_area_number my_areas.area_number%TYPE;
  
  l_t_area_code   my_areas.parent_area_code%TYPE;
  l_t_area_number my_areas.parent_area_number%TYPE;
  l_t_uqid        my_areas.parent_uqid%TYPE;
BEGIN 
  FOR i IN (
    with x as (
    select /*MATERIALIZE*/
         p.area_code p_area_code, p.area_number p_area_number, p.uqid p_uqid, p.name p_name, p.geom p_geom
--,        strava.uk_trim_suffix(u.name) u_other_words
--,        REGEXP_SUBSTR(u.name, '[^[:space:]]+$') u_last_word
,        u.area_code u_area_code, u.area_number u_area_number, u.uqid u_uqid, u.area_level u_area_level, u.name u_name, u.geom u_geom
,        t.area_code t_area_code, t.area_number t_area_number, t.uqid t_uqid, t.area_level t_area_level, t.name t_name, t.geom t_geom
,        strava.uk_trim_suffix(t.name) t_other_words
,        sdo_geom.relate(u.geom,'TOUCH',t.geom,1) touching
,        sdo_geom.relate(u.geom,'OVERLAPBDYINTERSECT',t.geom,1) overlapping
--,        round(sdo_geom.sdo_area(u.geom, unit=>'unit=sq_km'),3) settlement_km_sq
--,        round(sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km'),3) town_km_sq
--,        round(sdo_geom.sdo_area(sdo_geom.sdo_intersection(t.geom,u.geom,1), unit=>'unit=sq_km'),3) intersect_km_sq    
    from   my_areas t, my_areas u, my_areas p
    where  t.area_code LIKE '__W'
	and    u.area_code = 'UC'||substr(t.area_code,1,1)||'W'
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
	  ,      parent_uqid = l_union_area_code||l_union_area_number
	  ,      matchable = 0
	  ,	     name_hierarchy = ''
	  WHERE  area_code = i.t_area_code
	  AND    area_number = i.t_area_number;
	END IF;
  END LOOP;	
END;
/

----------------------------------------------------------------------------------------------------
--list new UC_W areas
----------------------------------------------------------------------------------------------------
select x.*
, sdo_geom.sdo_area(x.geom, unit=>'unit=sq_km')
from my_areas x
where (area_code like 'UC_W' or parent_area_code like 'UC_W')
;

----------------------------------------------------------------------------------------------------
--compare areas of consolidated and consituent areas
----------------------------------------------------------------------------------------------------
with u as (
select /*+MATERIALIZE*/ u.area_code, u.area_number, u.name
, sdo_geom.sdo_area(u.geom, unit=>'unit=sq_km') area_u
from my_areas u
where u.area_code like 'UC_W'
), t as (
select /*+MATERIALIZE*/ t.parent_area_code, t.parent_area_number, count(*) num_areas
, sum(sdo_geom.sdo_area(t.geom, unit=>'unit=sq_km')) area_t
from my_areas t
where t.parent_area_code like 'UC_W'
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
where area_code IN('TOWN','SETL','UCCW')
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
and p.area_code LIKE 'UC_W'
and c.area_code LIKE '__W'
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
and aa.area_code like 'UC_W'
/
----------------------------------------------------------------------------------------------------
--update related geometries
----------------------------------------------------------------------------------------------------
UPDATE my_areas
SET    mbr = sdo_geom.sdo_mbr(geom)
,      num_pts = SDO_UTIL.GETNUMVERTICES(geom)
where  area_code like 'UC_W'
and    (num_pts IS NULL or mbr IS NULL)
/
----------------------------------------------------------------------------------------------------
-- correct parent uqid 
----------------------------------------------------------------------------------------------------
merge into my_areas u
using (
select c.area_level, c.area_code, c.area_number, c.name
, c.parent_uqid, p.uqid uqid_of_parent
from my_areas c
  inner join my_areas p
    on p.area_code = c.parent_area_code
    and p.area_number = c.parent_area_number
where (c.parent_uqid IS NULL or c.parent_uqid!= p.uqid)
order by c.area_level
) s
ON (s.area_code = u.area_code AND s.area_number = u.area_number)
WHEN MATCHED THEN UPDATE 
SET u.parent_uqid = s.uqid_of_parent
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
--check no unfied area same as its parent
----------------------------------------------------------------------------------------------------
with x as (
SELECT c.area_Code c_area_Code, c.area_number c_area_number, c.name c_name, c.num_children c_num_children, round(sdo_geom.sdo_area(c.geom, unit=>'unit=sq_km'),3) c_area
,      p.area_Code p_Area_Code, p.area_number p_area_number, p.name p_name, p.num_children p_num_children, round(sdo_geom.sdo_area(p.geom, unit=>'unit=sq_km'),3) p_area
from my_areas c
  inner join my_areas p on p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
where c.area_code like 'UC_W'
)
select * from x
where p_num_children = 1
or c_area/p_area BETWEEN 0.99 and 1.01
/

----------------------------------------------------------------------------------------------------
-- mark child not matchable where matchable parent  has similar name
----------------------------------------------------------------------------------------------------
SELECT p.area_Code p_Area_Code, p.area_number p_area_number, p.name p_name, p.matchable p_matchable, p.num_children p_num_children, round(sdo_geom.sdo_area(p.geom, unit=>'unit=sq_km'),3) p_area
,      c.area_Code c_area_Code, c.area_number c_area_number, c.name c_name, c.matchable c_matchable, c.num_children c_num_children, round(sdo_geom.sdo_area(c.geom, unit=>'unit=sq_km'),3) c_area
from my_areas c
  inner join my_areas p on p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
where p.name = strava.uk_trim_suffix(c.name)
and p.matchable = 1
and c.area_code like '__W'
and c.matchable = 1
/
update my_areas c
set c.matchable = 0
where c.matchable = 1
and c.area_code like '__W'
and exists (
  select 'x'
  from my_areas p 
  where p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
  and p.name = strava.uk_trim_suffix(c.name)
);

----------------------------------------------------------------------------------------------------
-- mark child not matchable where matchable parent has same name
----------------------------------------------------------------------------------------------------
SELECT p.area_Code p_Area_Code, p.area_number p_area_number, p.name p_name, p.matchable p_matchable, p.num_children p_num_children, round(sdo_geom.sdo_area(p.geom, unit=>'unit=sq_km'),3) p_area
,      c.area_Code c_area_Code, c.area_number c_area_number, c.name c_name, c.matchable c_matchable, c.num_children c_num_children, round(sdo_geom.sdo_area(c.geom, unit=>'unit=sq_km'),3) c_area
from my_areas c
  inner join my_areas p on p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
where p.name = c.name
and p.matchable = 1
and c.matchable = 1
/
update my_areas c
set c.matchable = 0
where c.matchable = 1
and exists (
  select 'x'
  from my_areas p 
  where p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
  and p.name = c.name
  and p.matchable = 1
);

----------------------------------------------------------------------------------------------------
-- mark child not matchable where matchable parent has same leading name
----------------------------------------------------------------------------------------------------
SELECT p.area_Code p_Area_Code, p.area_number p_area_number, p.name p_name, p.matchable p_matchable, p.num_children p_num_children, round(sdo_geom.sdo_area(p.geom, unit=>'unit=sq_km'),3) p_area
,      c.area_Code c_area_Code, c.area_number c_area_number, c.name c_name, c.matchable c_matchable, c.num_children c_num_children, round(sdo_geom.sdo_area(c.geom, unit=>'unit=sq_km'),3) c_area
from my_areas c
  inner join my_areas p on p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
where c.name like p.name||' %'
and not c.name like p.name||'% with %'
--and c.area_code like '%W'
and p.matchable = 1
--and p.area_code IN('CPC','DIS')
and c.matchable = 1
/
update my_areas c
set c.matchable = 0
where c.matchable = 1
and c.area_code like '%W'
and exists (
  select 'x'
  from my_areas p 
  where p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
  and c.name like p.name||' %'
  and p.area_code IN('CPC','DIS','UTA','MTD','LBO')
  and p.matchable = 1
);
update my_areas c --mainly for France
set c.matchable = 0
where c.matchable = 1
and c.area_code like 'CANT'
and exists (
  select 'x'
  from my_areas p 
  where p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
  and c.name like p.name||' %'
  and p.area_code IN('DIS')
  and p.matchable = 1
);
update my_areas c --mainly for Gernamny
set c.matchable = 0
where c.matchable = 1
and c.area_code like 'UDIS'
and exists (
  select 'x'
  from my_areas p 
  where p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
  and c.name like p.name||'% Städte'
  and p.area_code IN('AREG')
  and p.matchable = 1
);

----------------------------------------------------------------------------------------------------
-- mark child matchable where matchable parent has same leading name with a with in the name
----------------------------------------------------------------------------------------------------
SELECT p.area_Code p_Area_Code, p.area_number p_area_number, p.name p_name, p.matchable p_matchable, p.num_children p_num_children, round(sdo_geom.sdo_area(p.geom, unit=>'unit=sq_km'),3) p_area
,      c.area_Code c_area_Code, c.area_number c_area_number, c.name c_name, c.matchable c_matchable, c.num_children c_num_children, round(sdo_geom.sdo_area(c.geom, unit=>'unit=sq_km'),3) c_area
from my_areas c
  inner join my_areas p on p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
where c.name like p.name||'% with %'
--and c.area_code like '%W'
and p.matchable = 1
--and p.area_code IN('CPC','DIS')
and c.matchable = 0
/
update my_areas c
set c.matchable = 1
where c.matchable = 0
and c.area_code like '%W'
and exists (
  select 'x'
  from my_areas p 
  where p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
  and c.name like p.name||'% with %'
  and p.area_code IN('CPC','DIS','UTA','MTD','LBO')
  and p.matchable = 1
);
----------------------------------------------------------------------------------------------------
-- childless non-matchable areas
----------------------------------------------------------------------------------------------------
SELECT p.area_code, p.area_number, p.name, p.num_children, p.matchable
,      c.area_code, c.area_number, c.name, c.num_children, c.matchable
,      (SELECT COUNT(*) FROM activity_areas aa WHERE aa.area_Code = c.area_Code AND aa.area_Number = c.area_number) num_activities
FROM my_areas p
  INNER JOIN my_areas c ON p.area_code = c.parent_area_code  and p.area_number = c.parent_area_number
WHERE c.matchable = 0
and (c.num_children = 0 or c.num_children IS NULL)
and not c.area_code IN('GEOU','GEOS')
and not p.area_code IN('SOV','GEOS')
/

----------------------------------------------------------------------------------------------------
-- all child areas are wards with same leading name as paraent
----------------------------------------------------------------------------------------------------
with x as (
SELECT p.area_code, p.area_number, p.name, p.num_children
, count(*) num_similarly_named_children
, sum(sign(c.matchable )) num_similarly_named_matchable_children
, listagg(c.name,', ') within group (order by c.name) list_of_children
FROM my_areas p
  INNER JOIN my_areas c ON c.parent_area_code = p.area_Code and c.parent_area_number = p.area_number AND c.name like p.name||' %'
where p.num_children > 1
and p.matchable = 1
and p.area_code = 'CPC'
--and p.name like '%Edenbridge%'
group by p.area_code, p.area_number, p.name, p.num_children
having count(*)=p.nuM_children
)
select * from x
where num_similarly_named_matchable_children > 0
/
