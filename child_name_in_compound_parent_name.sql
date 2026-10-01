REM child_name_in_compound_parent_namee.sql
REM child names within paraent name
select p.area_code,  p.name
     ,  c.area_code,  c.name
from my_areas p
  inner join my_areas c on c.parent_area_code = p.area_code and c.parent_area_number = p.area_number
where c.matchable = 1 and p.matchable = 1
--and regexp_like(p.name,  c.name,  'i')
and ' '||translate(p.name, ', -/', '   ')||' ' like '% '||c.name||' %'
and NOT c.area_code IN('GEOU', 'GEOS')
--and p.name = c.name
;

REM all children in parent
select p.area_code,  p.area_number,  p.name,  p.num_children
,       count(*) matching_children
,       LISTAGG(DISTINCT c.name, ',  ') within group (order by c.name) list_children
,       LISTAGG(DISTINCT c.area_code, ',  ') within group (order by c.name) list_child_types
from my_areas p
  inner join my_areas c on c.parent_area_code = p.area_code and c.parent_area_number = p.area_number
where p.num_children > 0
and c.matchable = 1
and p.matchable = 1
and ' '||translate(p.name, ', -/', '   ')||' ' like '% '||c.name||' %'
--and (p.area_code,  p.area_number) IN (SELECT distinct area_code,  area_number FROM activity_areas)
group by p.area_code,  p.area_number,  p.name,  p.num_children
having count(*) = p.num_children
order by 1, 2, 4, 5
/

update my_areas
set matchable = 0
where matchable = 1
and (  (parent_area_code = 'CANT' and parent_area_number IN(7940299, 7941112, 7941113, 7941114, 7942087, 7942088, 7942263, 7942745, 7943230, 7943246))
    or (parent_area_code = 'CPC' and parent_area_number IN(52052, 52440, 52749, 57409, 57672, 59460, 118484, 118765,119649, 124310))
    or (parent_area_code = 'DEPT' and parent_area_number IN(792046))
    or (parent_area_code = 'DIS' and parent_area_number IN(793006, 793220))
    or (parent_area_code = 'DIW' and parent_area_number IN(44011, 45560, 45564, 46143, 53062, 53066, 53301, 53483, 53486, 53552, 53577, 58264, 58743, 62007, 66111, 69244, 69322, 69346, 69743, 116125, 116180, 116630, 116664, 116677, 117195, 117835, 117994, 118149, 118329, 118721, 118722, 118761, 118773, 118775, 118776, 118879, 119143, 119147, 119198, 119335, 119341, 119612, 120487, 122086, 122201, 122212, 122275, 122277, 122287, 122299, 122346, 122376, 122974, 123590, 125803, 125885, 125907, 125908, 125946, 125951, 126065, 126136, 126359, 126411, 126441, 126519, 126609, 126656, 126683, 126685, 126931, 126932, 128384, 128414, 128418, 128451, 128574, 134066, 134101, 134179, 134330, 134440, 134478, 134527, 134563, 134599, 134612, 134671, 134673, 134686, 134687, 134795, 134826, 134829, 135086, 135137, 135620, 135907, 139610, 139642, 139651, 139735, 139746, 139757, 139775, 139820, 139826))
    or (parent_area_code = 'MTW' and parent_area_number IN(56670, 120065, 120141, 120286, 120314, 120318, 126741, 126742, 126959))
    or (parent_area_code = 'UTW' and parent_area_number IN(134270, 118392, 118826, 119272, 124662, 124664, 124667, 125013, 126533, 133810, 135235, 135837, 135842, 139550))
    or (parent_area_code = 'VWG' and parent_area_number IN(81155001, 81155002, 81155006, 81185006, 81195002, 81255005, 81275001, 82165001, 82165006, 83155011, 83165001, 83275003, 84255009, 84355001, 84365009, 93755334, 95735540, 95755520, 145215101, 145215110, 145215130, 145225129, 145235120, 145235134, 145245104, 145245118, 146265214, 146265228, 146275234, 146285209, 147305306, 147305311))
    )
/

