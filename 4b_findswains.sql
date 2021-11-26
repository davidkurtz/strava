REM 4b_findswains.sql
Column activity_id heading 'Activity|ID' format 9999999999
Column activity_name format a30
column distance_km heading 'Distance|Km' format 999.99
Column geom_relate heading 'geom|relate' format a6
spool 4b_findswains
With a as (
SELECT a.activity_id, a.activity_date, a.activity_name, a.distance_km
--,      SDO_GEOM.RELATE(a.geom,'anyinteract',g.geom,25) geom_relate
FROM   activities a
,      my_geometries g
WHERE  a.activity_type = 'Ride'
--And    a.activity_id IN(4468006769)
And    a.activity_date >= TO_DATE('01072020','DDMMYYYY')
and    g.geom_id = 2 /*Swains World Route*/
AND    SDO_ANYINTERACT(a.geom, g.geom) = 'TRUE'
)
Select *
From   a
--Where  geom_relate = 'TRUE'
Order by activity_date
/
spool off