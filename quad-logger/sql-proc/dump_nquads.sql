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

    DECLARE nquad, buffer, excludes, at_checkpoint, startdate, currenttrx, rst ANY;
    DECLARE inx           INT;
    DECLARE cpinterval    INTEGER;

    startdate := datestring_GMT(now());
    SET isolation = 'serializable';

    result_names(nquad);
    buffer := dict_new(); -- Dictionary objects are always passed by reference.

    -- disable automatic checkpoints during dump.
    cpinterval := checkpoint_interval (-1);

    DECLARE EXIT HANDLER FOR SQLSTATE '*' {
        checkpoint_interval (cpinterval);
        result(concat('# ERROR [', __SQL_STATE, '] ',  __SQL_MESSAGE));
        resignal;
    };

    -- Set a checkpoint
    EXEC ('CHECKPOINT');
    -- Full path to current transaction file.
    currenttrx := cfg_item_value(virtuoso_ini_path(), 'Database', 'TransactionFile');
    at_checkpoint := right(regexp_replace(currenttrx, '[^0-9]', ''), 14);

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
        vql_buffer_nquad('+', "s", "p", "o", "g", buffer, at_checkpoint, maxq);
        inx := inx + 1;
    }

    -- output the rest of the buffer
    vql_print_buffer(buffer, at_checkpoint);

    -- start a report
    result(concat('# at checkpoint  ', at_checkpoint));
    result(concat('# dump started   ', startdate));

    -- Datetime string in name of transaction logs has seconds resolution.
    -- Set the next checkpoint at least 1 second later than at_checkpoint.
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
    result(concat('# dump completed ', datestring_GMT(now())));
    result(concat('# quad count     ', inx));
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