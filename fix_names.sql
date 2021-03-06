REM fix_names.sql

set pages 99 lines 180
column name format a60
Alter table my_areas add suffix varchar2(20);

Select distinct area_code, SUBSTR(name,1,LENGTH(name)-7) name
from my_areas Where 
name like '%County'
/
Update my_areas
Set suffix = 'County', name = SUBSTR(name,1,LENGTH(name)-7)
Where area_code = 'CTY'
And name like '%County'
/
----------
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-10) name
from my_areas Where name like '%Authority'
/
Update my_areas
Set suffix = 'Authority', name = SUBSTR(name,1,LENGTH(name)-10)
Where area_code = 'GLA'
And name like '%Authority'
/
----------
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-9) name
from my_areas Where name like '%District'
/
Update my_areas
Set suffix = 'District', name = SUBSTR(name,1,LENGTH(name)-9)
Where area_code = 'DIS'
And name like '%District'
/
----------
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-13) name
from my_areas Where 
name like '%District (B)'
/
Update my_areas
Set suffix = 'District', name = SUBSTR(name,1,LENGTH(name)-13)
Where area_code IN('DIS','MTD')
And name like '%District (B)'
/
----------
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-12) name
from my_areas Where 
name like '%London Boro'
/
Update my_areas
Set suffix = 'London Borough', name = SUBSTR(name,1,LENGTH(name)-12)
Where area_code = 'LBO'
And name like '%London Boro'
/
----------
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-4) name
from my_areas Where 
name like '% (B)'
/
Update my_areas
Set suffix = '(B)', name = SUBSTR(name,1,LENGTH(name)-4)
Where area_code IN('UTA')
And name like '% (B)'
/
----------
Select distinct area_code, name, suffix from my_areas 
/
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-11) name
from my_areas Where 
name like '%Ward (DET)'
/
Update my_areas
Set suffix = 'Ward (DET)', name = SUBSTR(name,1,LENGTH(name)-11)
Where area_code IN('DIW')
And name like '%Ward (DET)'
/
----------
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-5) name
from my_areas Where 
name like '%Ward'
/
Update my_areas
Set suffix = 'Ward', name = SUBSTR(name,1,LENGTH(name)-5)
Where area_code IN('UTW','DIW','MTW','LBW')
And name like '%Ward'
/
----------
Select distinct area_code, SUBSTR(name,9) name
from my_areas Where 
name like 'LCPs of %'
/
Update my_areas
Set suffix = 'LCPs', name = SUBSTR(name,9)
Where area_code IN('CPC')
And name like 'LCPs of %'
/
----------
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-3) name
from my_areas Where 
name like '%CP'
/
Update my_areas
Set suffix = 'CP', name = SUBSTR(name,1,LENGTH(name)-3)
Where area_code IN('CPC')
And name like '%CP'
/
----------
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-9) name
from my_areas Where 
name like '%CP (DET)'
/
Update my_areas
Set suffix = 'CP (DET)', name = SUBSTR(name,1,LENGTH(name)-9)
Where area_code IN('CPC')
And name like '%CP (DET)'
/
----------
Select distinct area_code, SUBSTR(name,1,LENGTH(name)-10) name
from my_areas Where 
name like '%Community'
/
Update my_areas
Set suffix = 'Community', name = SUBSTR(name,1,LENGTH(name)-10)
Where area_code IN('CPC')
And name like '%Community'
/
----------
Select distinct suffix from my_areas
/
Select distinct area_code, area_level, suffix from my_areas
order by 2,1
/
Select distinct area_code, name, suffix 
from my_areas
Where suffix is null
/
----------
Alter table my_areas modify suffix null;
Select distinct area_code, suffix from my_areas 
/
