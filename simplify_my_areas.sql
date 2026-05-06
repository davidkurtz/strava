REM simplify_my_areas.sql
clear screen
set serveroutput on echo on timi on
spool simplify_my_areas.lst

/*
update my_areas
set num_pts = SDO_UTIL.GETNUMVERTICES(geom)
where num_pts IS NULL
*/

DECLARE
  k_tolerance CONSTANT NUMBER := 0.01;
  l_counter INTEGER := 0;
BEGIN
  FOR i IN (
    with x as (
    select a.*
    ,      sdo_util.simplify(geom,1,k_tolerance) new_geom
    from my_areas a
    --order by num_pts desc nulls first
    --fetch first 500 rows only
    )
    select area_code, area_number, name
    ,      geom,  SDO_UTIL.GETNUMVERTICES(geom) org_num_pts, sdo_geom.sdo_area(geom, unit=>'unit=sq_km') org_area_sq_km
    ,      new_geom,  SDO_UTIL.GETNUMVERTICES(new_geom) new_num_pts, sdo_geom.sdo_area(new_geom, unit=>'unit=sq_km') new_area_sq_km
    from x
  ) LOOP
    IF i.new_num_pts/i.org_num_pts<.9 AND ABS(i.org_area_sq_km-i.new_area_sq_km)<0.01 THEN
      l_counter := l_counter + 1;
      dbms_output.put_line(l_counter||':'||i.area_code||'-'||i.area_number||':'||i.name
  	                    ||': num_pts:'||i.org_num_pts||'->'||i.new_num_pts
 						||': area:'||round(i.org_area_sq_km,4)||'->'||round(i.new_area_sq_km,4)
                        );
      UPDATE my_areas
      SET    geom = i.new_geom
      ,      num_pts = i.new_num_pts
      WHERE  area_code = i.area_code
      AND    area_number = i.area_number
      and    name = i.name;
      --dbms_output.put_line(sql%rowcount||' rows updated');
      commit;
    END IF;
  END LOOP;
  --dbms_output.put_line('Total:'||l_counter||' rows updated');
END;
/

spool OFF

