REM fix_combi_names_matchablility3.sql
clear screen
set serveroutput on 
spool fix_combi_names_matchablility3.lst
BEGIN
  FOR i IN (
    select p.area_code p_area_code, p.area_number p_area_number, p.name  p_name, p.matchable p_matchable, round(sdo_geom.sdo_area(p.geom, unit=>'unit=sq_km'),3) p_area, p.num_children p_num_children
    ,     c1.area_code c1_area_Code, c1.area_number c1_area_number, c1.name c1_name, c1.matchable c1_matchable, round(sdo_geom.sdo_area(c1.geom, unit=>'unit=sq_km'),3) c1_area
    ,     c2.area_code c2_area_code, c2.area_number c2_area_number, c2.name c2_name, c2.matchable c2_matchable, round(sdo_geom.sdo_area(c2.geom, unit=>'unit=sq_km'),3) c2_area
    ,     c3.area_code c3_area_code, c3.area_number c3_area_number, c3.name c3_name, c3.matchable c3_matchable, round(sdo_geom.sdo_area(c3.geom, unit=>'unit=sq_km'),3) c3_area
    from my_areas p
      inner join my_areas c1 on c1.parent_area_Code = p.area_code and c1.parent_area_number = p.area_number and p.name like c1.name||'%'
      inner join my_areas c2 on c2.parent_area_Code = p.area_code and c2.parent_area_number = p.area_number and p.name like '%'||c2.name||'%'
	  inner join my_areas c3 on c3.parent_area_Code = p.area_code and c3.parent_area_number = p.area_number and p.name like '%'||c3.name
    where c1.rowid != c2.rowid AND c2.rowid != c3.rowid AND c3.rowid != c1.rowid
	--and c1.area_code = c2.area_Code and c2.area_Code = c3.area_Code and c3.area_Code = c1.area_code
    and NOT p.area_code IN('SOVC')
    and (p.name = c1.name||', '||c2.name||' and '||c3.name
	  or p.name = c1.name||', '||c2.name||' '||chr(38)||' '||c3.name)
    and (p.matchable = 1 or c1.matchable = 0 or c2.matchable = 0 or c3.matchable = 0)
	and p.num_children = 3
    --fetch first 50 rows only
  ) LOOP
    IF i.p_matchable = 1 THEN
      UPDATE my_areas
      SET    matchable    = 0
      WHERE  area_Code   = i.p_area_Code
      AND    area_number = i.p_area_number;
      dbms_output.put_line(i.p_area_Code||'-'||i.p_area_number||':'||i.p_name||' '||i.p_num_children||' children, set matchable=0');
    END IF;
    IF i.c1_matchable = 0 THEN
      UPDATE my_areas
      SET    matchable   = 1
      WHERE  area_Code   = i.c1_area_Code
      AND    area_number = i.c1_area_number;
      dbms_output.put_line(i.c1_area_Code||'-'||i.c1_area_number||':'||i.c1_name||'('||i.c1_area||' sqKm) set matchable=1');
    END IF;
    IF i.c2_matchable = 0 THEN
      UPDATE my_areas
      SET    matchable   = 1
      WHERE  area_Code   = i.c2_area_Code
      AND    area_number = i.c2_area_number;
      dbms_output.put_line(i.c2_area_Code||'-'||i.c2_area_number||':'||i.c2_name||'('||i.c2_area||' sqKm) set matchable=1');
    END IF;
    IF i.c3_matchable = 0 THEN
      UPDATE my_areas
      SET    matchable   = 1
      WHERE  area_Code   = i.c3_area_Code
      AND    area_number = i.c3_area_number;
      dbms_output.put_line(i.c3_area_Code||'-'||i.c3_area_number||':'||i.c3_name||'('||i.c3_area||' sqKm) set matchable=1');
    END IF;
  END LOOP;
END;
/


spool off

/*
select * from my_areas
where name like '%Wrotham%'
or name like '%Igtham%'
or name like '%Stanstead%'
/
select * from my_Area
where area_code like '__W'
/
*/