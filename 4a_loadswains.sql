REM 4a_loadswains.sql
set echo on
spool 4a_loadswains
delete from my_geometries;
commit;

INSERT INTO my_geometries (geom_id, descr, geom) 
VALUES(1,'Swains World Box',
  SDO_GEOMETRY(
    2003,  -- two-dimensional polygon
    4326,
    NULL,
    SDO_ELEM_INFO_ARRAY(1,1003,1), -- one polygon (exterior polygon ring clockwise)
    SDO_ORDINATE_ARRAY(-0.14770468632509, 51.569613039632 /*Swains World*/
                      ,-0.14832964102552, 51.569407978151 
                      ,-0.14674177328872, 51.567090552402 
                      ,-0.14592101733016, 51.567080548869 
                      ,-0.14770468632509, 51.569613039632 
                      )
    )
);

INSERT INTO my_geometries (geom_id, descr, gpx) 
VALUES (2,'Swains World Route', XMLTYPE(getClobDocument('STRAVA','swainsworldroute.gpx')));
 
UPDATE my_geometries
SET geom = mdsys.sdo_geometry(2002,4326,null,mdsys.sdo_elem_info_array(1,2,1),
cast(multiset(
  select CASE n.rn WHEN 1 THEN pt.lng WHEN 2 THEN pt.lat END ord
  from (
    SELECT /*+MATERIALIZE*/ rownum rn
    ,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'rtept/@lon')) as lng
    ,      TO_NUMBER(EXTRACTVALUE(VALUE(t), 'rtept/@lat')) as lat
    FROM   my_geometries g,
           TABLE(XMLSEQUENCE(extract(g.gpx,'/gpx/rte/rtept','xmlns="http://www.topografix.com/GPX/1/1"'))) t
    where g.geom_id = 2
    ) pt,
    (select 1 rn from dual union all select 2 from dual) n order by pt.rn, n.rn) AS mdsys.sdo_ordinate_array
))
WHERE gpx IS NOT NULL
AND   geom IS NULL
/
UPDATE my_geometries
SET mbr = sdo_geom.sdo_mbr(geom)
,   geom_27700 = sdo_cs.transform(geom,27700)
/

select * from my_geometries;
commit;
spool off
