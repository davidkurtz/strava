REM fix_combi_names_matchablility.sql
clear screen
set serveroutput on 
spool fix_combi_names_matchablility.lst
BEGIN
  FOR i IN (
    select p.area_code  p_area_code,  p.area_number  p_area_number,  p.name  p_name, p.matchable p_matchable, p.num_children p_num_children
    ,     c1.area_code c1_area_Code, c1.area_number c1_area_number, c1.name c1_name, c1.matchable c1_matchable
    ,     c2.area_code c2_area_code, c2.area_number c2_area_number, c2.name c2_name, c2.matchable c2_matchable
    from my_areas p
      inner join my_areas c1 on c1.parent_area_Code = p.area_code and c1.parent_area_number = p.area_number and p.name like c1.name||'%'
      inner join my_areas c2 on c2.parent_area_Code = p.area_code and c2.parent_area_number = p.area_number and p.name like '%'||c2.name
    where c1.rowid != c2.rowid
    and NOT p.area_code IN('SOVC')
    and (p.name = c1.name||' '||CHR(38)||' '||c2.name
    or   p.name = c1.name||', '||c2.name
    or   p.name = c1.name||' and '||c2.name
    or   p.name = c1.name||' with '||c2.name)
    and (p.matchable = 0 or c1.matchable = 1 or c2.matchable = 1)
	and p.num_children > 2
    --fetch first 50 rows only
  ) LOOP
    IF i.p_matchable = 0 THEN
      UPDATE my_areas
      SET    matchable    = 1
      WHERE  area_Code   = i.p_area_Code
      AND    area_number = i.p_area_number;
      dbms_output.put_line(i.p_area_Code||'-'||i.p_area_number||':'||i.p_name||' '||i.p_num_children||' children, set matchable=1');
    END IF;
    IF i.c1_matchable = 1 THEN
      UPDATE my_areas
      SET    matchable   = 0
      WHERE  area_Code   = i.c1_area_Code
      AND    area_number = i.c1_area_number;
      dbms_output.put_line(i.c1_area_Code||'-'||i.c1_area_number||':'||i.c1_name||' set matchable=0');
    END IF;
    IF i.c2_matchable = 1 THEN
      UPDATE my_areas
      SET    matchable   = 0
      WHERE  area_Code   = i.c2_area_Code
      AND    area_number = i.c2_area_number;
      dbms_output.put_line(i.c2_area_Code||'-'||i.c2_area_number||':'||i.c2_name||' set matchable=0');
    END IF;
  END LOOP;
END;
/


BEGIN
  FOR i IN (
    select p.area_code  p_area_code,  p.area_number  p_area_number,  p.name  p_name, p.matchable p_matchable, p.num_children p_num_children
    ,     c1.area_code c1_area_Code, c1.area_number c1_area_number, c1.name c1_name, c1.matchable c1_matchable
    ,     c2.area_code c2_area_code, c2.area_number c2_area_number, c2.name c2_name, c2.matchable c2_matchable
    from my_areas p
      inner join my_areas c1 on c1.parent_area_Code = p.area_code and c1.parent_area_number = p.area_number and p.name like c1.name||'%'
      inner join my_areas c2 on c2.parent_area_Code = p.area_code and c2.parent_area_number = p.area_number and p.name like '%'||c2.name
    where c1.rowid != c2.rowid
    and NOT p.area_code IN('SOVC')
    and (p.name = c1.name||' '||CHR(38)||' '||c2.name
    or   p.name = c1.name||', '||c2.name
    or   p.name = c1.name||' and '||c2.name
    or   p.name = c1.name||' with '||c2.name)
    and (p.matchable = 1 or c1.matchable = 0 or c2.matchable = 0)
	and p.num_children = 2
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
      dbms_output.put_line(i.c1_area_Code||'-'||i.c1_area_number||':'||i.c1_name||' set matchable=1');
    END IF;
    IF i.c2_matchable = 0 THEN
      UPDATE my_areas
      SET    matchable   = 1
      WHERE  area_Code   = i.c2_area_Code
      AND    area_number = i.c2_area_number;
      dbms_output.put_line(i.c2_area_Code||'-'||i.c2_area_number||':'||i.c2_name||' set matchable=1');
    END IF;
  END LOOP;
END;
/

spool off

/*
select * from my_areas
where name like '%Farningham%'
or name like '%Horton Kirby%'
or area_number = 122320
/
select * from my_areas
where name like '%Benson%'
or name like '%Crowmarsh%'
or parent_uqid = 'E05009733'
/
select * from my_areas
where name like '%Eltham%'
or uqid = 'E09000011'
/
*/