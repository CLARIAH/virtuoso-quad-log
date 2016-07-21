-- See also http://virtuoso.openlinksw.com/dataspace/doc/dav/wiki/Main/VirtRDFDumpNQuad

-- Dump all quads as rdf-patch-formatted resultset.
-- Parameters:
--      maxq: at each interval of maxq results, the outputstream will be marked with comments.
--              Comments are lines starting with hashes ('#').
--              This is a way to control the maximum amount of quads per dump file.
--              Default value: 100000
--      excluded_graphs: a space-separated string of graph iris that will be excluded from the dump.
--              Default value is -, not excluding graphs. (Default value '' (empty string) hits on errors.)
CREATE PROCEDURE vql_dump_nquads(IN maxq INT := 100000, IN excluded_graphs VARCHAR := '-') {

    DECLARE nquad, excludes, chckp, date2, startdate, currenttrx, rst ANY;
    DECLARE inx, cpc      INT;
    DECLARE cpinterval    INTEGER;

    SET isolation = 'serializable';

    result_names(nquad);

    -- disable automatic checkpoints during dump.
    cpinterval := checkpoint_interval (-1);

    DECLARE EXIT HANDLER FOR SQLSTATE '*' {
        checkpoint_interval (cpinterval);
        result(concat('# ERROR [', __SQL_STATE, '] ',  __SQL_MESSAGE));
        resignal;
    };

    chckp := 0;
    date2 := 1;
    cpc := 0;

    -- It's a pity that   EXEC ('CHECKPOINT')   does not return a timestamp.
    -- Pin down the checkpoint between two points in time.
    -- If the two points are equal as expressed with seconds precision,
    -- then the checkpoint occurred at that time.
--    WHILE (chckp <> date2 AND cpc < 3) {
--        startdate := datestring_GMT(now());
--        chckp := left(regexp_replace(startdate, '[^0-9]', ''), 14);
--        EXEC ('CHECKPOINT');
--        date2 := left(regexp_replace(datestring_GMT(now()), '[^0-9]', ''), 14);
--        cpc := cpc + 1;
--    }

--    IF (chckp <> date2) {
--        -- This will/should/could never happen?
--        result(concat('# ERROR CAUSE ', chckp, ' <> ', date2));
--        -- signal('DMPER', ': Could not get unequivocal checkpoint. Try again some other time.');
--        signal('DMPER', concat('ERROR CAUSE ', chckp, ' <> ', date2, ' : Could not get unequivocal checkpoint. Try again some other time.'));
--    }

    -- Set a checkpoint
    EXEC ('CHECKPOINT');
    -- Full path to current transaction file.
    currenttrx := cfg_item_value(virtuoso_ini_path(), 'Database', 'TransactionFile');
    chckp := right(regexp_replace(currenttrx, '[^0-9]', ''), 14);

    -- See note at foot of procedure.
    excludes := split_and_decode(excluded_graphs, 0, '\0\0 ');

    inx := 0;

    FOR (SELECT * FROM (sparql
            define input:storage ""
            define input:param "excludes"
            SELECT ?s ?p ?o ?g { GRAPH ?g { ?s ?p ?o } .
                FILTER ( bif:position(?g, ?:excludes) = 0 )
            } ) AS sub OPTION (loop)) DO
    {
        IF (mod(inx, maxq) = 0) {
            result(concat('# at checkpoint   ', chckp));
            result(concat('# dump started    ', startdate));
            result(concat('# quad count      ', inx));
        }
        result(vql_create_nquad('+', "s", "p", "o", "g"));
        inx := inx + 1;
    }
    result(concat('# at checkpoint   ', chckp));
    result(concat('# dump started    ', startdate));

    -- Datetime string in name of transaction logs has seconds resolution.
    -- Set the next checkpoint at least 1 second later than chckp.
    delay(1);

    -- See if currenttrx is stil the current transaction log.
    IF (currenttrx <> cfg_item_value(virtuoso_ini_path(), 'Database', 'TransactionFile')) {
        signal('DMPER', concat(': A checkpoint has been executed since start of dump at ', startdate, '. Dump invalid.'));
    }
    EXEC ('CHECKPOINT');

    -- Enable automatic checkpoints with saved interval.
    checkpoint_interval (cpinterval);

    -- See if currenttrx is free of transactions...
    rst := vql_check_trx(currenttrx);
    IF (rst[0] > 0 OR rst[1] > 0) {
        signal('DMPER', concat(': There have been ', rst[0], ' inserts and ', rst[1], ' deletes during dump. Dump invalid.'));
    }

    -- Mark the dump as completed.
    result(concat('# dump completed  ', datestring_GMT(now())));
    result(concat('# quad count      ', inx));
    result(concat('# excluded graphs ', excluded_graphs));
}
;
-- [Note]
-- Syntax for setting the parameter -excludes- inside the SPARQL query:
--      define input:param "excludes"
-- Inside the SPARQL query we can refer to it by ?:excludes
-- The call to a build-in-function is prefixed with bif:
--      FILTER ( bif:position(?g, ?:excludes) = 0 )
-- If we had our own procedure defined with
--      CREATE PROCEDURE vql_exclude_iri(IN iri ANY, IN excludes ANY)
-- , we could have called that one with prefix sql:
--      FILTER ( sql:vql_exclude_iri(?g, ?:excludes) = 0 )


CREATE PROCEDURE vql_check_trx (IN f VARCHAR) {
    DECLARE h, op, inserts, deletes, line, lines ANY;
    DECLARE pos INT;

    inserts := 0;
    deletes := 0;

    h := file_open (f, 0);
    WHILE ((lines := read_log (h, pos)) is not null) {
        DECLARE quad ANY;
        DECLARE i INT;
        quad := null;

        FOR (i := 0; i < length (lines); i := i + 1) {
            line := lines[i];
            IF (line[0] in (1, 8, 9, 13)) { -- LOG_INSERT, LOG_INSERT_SOFT, LOG_INSERT_REPL and LOG_KEY_INSERT are all additions
                op := '+';
                IF (line[0] = 13) {
                    quad := line[2]; -- with LOG_KEY_INSERT a flag is inserted in the line so the quad ends up in line[2] instead of line[1]
                }
                ELSE {
                    quad := line[1];
                }
            }
            ELSE if (line[0] in (3, 14)) {-- LOG_DELETE and LOG_KEY_DELETE are both deletions
                op := '-';
                quad := line[1];
            }

            IF (quad is not null) { --if the operation was in one of the handled cases
                IF (quad[0] = 271) {
                    --There are a few tables and indexes that store the quads (select * from SYS_KEYS WHERE KEY_NAME like '%QUAD%')
                    --The log contains a record for each index. It seems to me that the table DB.DBA.RDF_QUAD (id=271) is the one
                    --that's always updated. So we can ignore the others
                    IF (op = '+') {
                        inserts := inserts + 1;
                    }
                    IF (op = '-') {
                        deletes := deletes + 1;
                    }
                }
            }
        }
    }
    return vector(inserts, deletes);
}
;