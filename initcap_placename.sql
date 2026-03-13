REM initcap_placename.sql
clear screen
set echo on termout on serveroutput on 
spool initcap_placename.lst
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION initcap_placename(p_text IN VARCHAR2)
  RETURN VARCHAR2
IS
  l_result      VARCHAR2(4000) := '';
  l_token       VARCHAR2(400);
  l_newtoken    VARCHAR2(400);
  l_pos         PLS_INTEGER := 1;
  l_word_count  PLS_INTEGER := 0;

  ----------------------------------------------------------------------------------------------------
  -- Words that stay lowercase unless first word
  ----------------------------------------------------------------------------------------------------
  FUNCTION is_small_word(p_word VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    RETURN LOWER(p_word) IN (
      -- English
      'and','or','of','the','in','on','at','to','for','by','with',
      'from','under','over','between','into','onto','upon',

      -- Irish
      'na','ní','de','den','an','mhic','uí',

      -- French / general European particles
      'le','la','les','du','des','d','l','di','da','do','dos','das',
      'van','von','der','den','ter','ten'
    );
  END is_small_word;
  ----------------------------------------------------------------------------------------------------
  -- Preserve acronyms (all uppercase words)
  ----------------------------------------------------------------------------------------------------
  FUNCTION is_acronym(p_word VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    RETURN REGEXP_LIKE(p_word, '^[[:upper:]]+$');
  END is_acronym;

  ----------------------------------------------------------------------------------------------------
  -- Capitalise handling apostrophes correctly
  ----------------------------------------------------------------------------------------------------
  FUNCTION cap_apostrophe(p_word VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    --from the start of string match apostrophe or hypen, followed by an alphabetic character
	--then replace it with the first character followed by upper case of second character
    RETURN REGEXP_REPLACE(
             p_word,
             '(^|''|-)([[:alpha:]])',
             '\1' || UPPER('\2')
           );
  END;
  ----------------------------------------------------------------------------------------------------
  -- Capitalise hyphenated segments individually
  ----------------------------------------------------------------------------------------------------
  FUNCTION cap_hyphenated(p_word VARCHAR2) RETURN VARCHAR2 IS
    l_out   VARCHAR2(400) := '';
    l_part  VARCHAR2(200);
    l_idx   PLS_INTEGER := 1;
  BEGIN
    LOOP
      l_part := REGEXP_SUBSTR(p_word, '[^-]+', 1, l_idx);
      EXIT WHEN l_part IS NULL;

      IF l_idx > 1 THEN
        l_out := l_out || '-';
      END IF;

      l_out := l_out || cap_apostrophe(l_part);

      l_idx := l_idx + 1;
    END LOOP;

    RETURN l_out;
  END cap_hyphenated;
  ----------------------------------------------------------------------------------------------------
  -- Capitalize word after hypen
  ----------------------------------------------------------------------------------------------------
  FUNCTION cap_word(p_word VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN REGEXP_REPLACE(
        p_word,
        '(^|[-''])([[:alpha:]])',
        '\1'||UPPER('\2')
    );
  END;
----------------------------------------------------------------------------------------------------
BEGIN
  IF p_text IS NULL THEN
    RETURN NULL;
  END IF;

  LOOP
    -- Match either whitespace OR non-whitespace token - \s is a whitespace character, \S is a non whitespace
    l_token := REGEXP_SUBSTR(p_text, '(\s+|\S+)', 1, l_pos);
    EXIT WHEN l_token IS NULL;

    IF REGEXP_LIKE(l_token, '^\s+$') THEN
      -- Preserve whitespace exactly
      l_result := l_result || l_token;
    ELSE
      -- Word token
      l_word_count := l_word_count + 1;

      IF l_word_count = 1 THEN
        -- First word always capitalized
        l_newtoken := initcap(l_token);
      ELSIF is_small_word(l_token) THEN
        -- Small words lowercase
        l_newtoken := LOWER(l_token);
      ELSE
        -- Regular words capitalized
        l_newtoken := initcap(l_token);
      END IF;
	  --dbms_output.put_line(l_word_count||l_token||'->'||l_newtoken);
	  l_result := l_result || l_newtoken;
    END IF;

    l_pos := l_pos + 1;
  END LOOP;

  RETURN l_result;
END initcap_placename;
----------------------------------------------------------------------------------------------------
/

select initcap_placename('richmond and KINGSTON-UPon-thames');

spool off
