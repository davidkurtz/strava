REM fix_unicode.sql

select * from my_areas
where name like 'Eng%air';

--german umlaut

update my_areas 
set name = replace(name,'ã¼N','ü')
where name like '%ã¼N%'
/
update activities
set name = replace(name,'ã¼N','ü')
where name like '%ã¼N%'
/
update activities
set description = replace(description,'ã¼N','ü')
where description like '%ã¼N%'
/


--Engiadina Bassa/Val Mã¼Stair
update my_areas 
set name = replace(name,'ã¼S','üs')
where name like '%ã¼S%'
/
update activities
set name = replace(name,'ã¼S','üs')
where name like '%ã¼S%'
/
update activities
set description = replace(description,'ã¼S','üs')
where description like '%ã¼S%'
/
