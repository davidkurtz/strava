REM adb_create_credentials.sql

clear screen
SET SERVEROUTPUT ON;
spool adb_create_credentials.lst

DECLARE
    l_bucket_uri VARCHAR2(4000);
BEGIN
    -- 1️⃣ Drop old credential if it exists
    BEGIN
        DBMS_CLOUD.DROP_CREDENTIAL('OBJECT_STORE_CRED');
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('No existing credential to drop.');
    END;

    -- 2️⃣ Create new credential with S3 keys
    DBMS_CLOUD.CREATE_CREDENTIAL(
        credential_name => 'OBJECT_STORE_CRED',
        username        => '<ACCESS KEY>',   -- Replace with your Access Key
        password        => '<SECRET KEY>'    -- Replace with your Secret Key
    );

    DBMS_OUTPUT.PUT_LINE('Credential OBJECT_STORE_CRED created successfully.');

    -- 3️⃣ Set bucket URI
    l_bucket_uri := 'https://objectstorage.uk-london-1.oraclecloud.com/n/lrp1qmpxv8ea/b/bucket-gofaster1/o/';
    -- Replace <NAMESPACE> and <BUCKET> with actual values

    -- 4️⃣ List objects in bucket to verify access
    DBMS_OUTPUT.PUT_LINE('Listing objects in bucket...');
    FOR r IN (
        SELECT *
        FROM TABLE(
            DBMS_CLOUD.LIST_OBJECTS(
                credential_name => 'OBJECT_STORE_CRED',
                location_uri    => l_bucket_uri
            )
        )
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(r.object_name);
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Bucket listing completed successfully.');
END;
/

spool off
