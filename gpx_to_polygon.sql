REM gpx_to_polygon.sql

CREATE OR REPLACE PROCEDURE gpx_to_polygon_sql 
(p_gpx_clob     IN  CLOB
,p_area_number  IN  NUMBER
,p_sql_out      OUT CLOB
) IS
    v_xml        XMLTYPE;
    v_coords     CLOB := '';

    v_first_lat  NUMBER;
    v_first_lon  NUMBER;

    v_last_lat   NUMBER;
    v_last_lon   NUMBER;

    v_lat        NUMBER;
    v_lon        NUMBER;

    v_sep        VARCHAR2(1) := '(';
    v_first      BOOLEAN := TRUE;

	k_lf         CONSTANT VARCHAR2(1) := CHR(10);
BEGIN
    -- Convert GPX CLOB to XML
    v_xml := XMLTYPE(p_gpx_clob);

    -- Extract route/track points
    FOR r IN (
        SELECT lat, lon FROM XMLTABLE(
            '//*[local-name()="trkpt" or local-name()="rtept"]'
            PASSING v_xml
            COLUMNS
                lat NUMBER PATH '@lat',
                lon NUMBER PATH '@lon'
        )
    )
    LOOP
        v_lat := r.lat;
        v_lon := r.lon;

        -- Append coordinate
        v_coords := v_coords || v_sep || v_lon || ',' || v_lat || k_lf;

        -- Store first point
        IF v_first THEN
            v_first_lat := v_lat;
            v_first_lon := v_lon;
            v_first := FALSE;
			v_sep := ',';
        END IF;

        -- Store last point
        v_last_lat := v_lat;
        v_last_lon := v_lon;
    END LOOP;

    -- Ensure polygon is closed
    IF v_first_lon != v_last_lon OR v_first_lat != v_last_lat THEN
        v_coords := v_coords || v_first_lon || ',' || v_first_lat;
    END IF;

    -- Build INSERT statement
    p_sql_out :=
           'INSERT INTO stage_my_areas (user_code, user_number, geom) VALUES ('
        || '''USER'', '||p_area_number
        || ', SDO_GEOMETRY('
        || '2003, 4326, NULL, '
        || 'SDO_ELEM_INFO_ARRAY(1,1003,1), '
        || 'SDO_ORDINATE_ARRAY'
        || v_coords
        || ')'
        || '));';

END;
/