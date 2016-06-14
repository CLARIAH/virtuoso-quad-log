-- See also http://virtuoso.openlinksw.com/dataspace/doc/dav/wiki/Main/VirtRDFDumpNQuad

CREATE PROCEDURE vql_dump_nquads(IN maxq INT := 100000) {

    DECLARE nquad, chckp, date2, startdate, currenttrx, rst ANY;
    DECLARE inx, cpc      INT;
    DECLARE cpinterval    INTEGER;

    SET isolation = 'serializable';

    -- disable automatic checkpoints during dump.
    cpinterval := checkpoint_interval (-1);

    chckp := 0;
    date2 := 1;
    cpc := 0;

    -- It's a pity that   EXEC ('CHECKPOINT')   does not return a timestamp.
    -- Pin down the checkpoint between two points in time.
    -- If the two points are equal as expressed with seconds precision,
    -- then the checkpoint occurred at that time.
    WHILE (chckp <> date2 AND cpc < 3) {
        startdate := datestring_GMT(now());
        chckp := left(regexp_replace(startdate, '[^0-9]', ''), 14);
        EXEC ('CHECKPOINT');
        date2 := left(regexp_replace(datestring_GMT(now()), '[^0-9]', ''), 14);
        cpc := cpc + 1;
    }
    -- Full path to current transaction file.
    currenttrx := cfg_item_value(virtuoso_ini_path(), 'Database', 'TransactionFile');

    IF (chckp <> date2) {
        -- This will/should/could never happen?
        signal('99999', ': Could not get unequivocal checkpoint. Try again some other time.');
    }

    inx := 0;
    result_names(nquad);

    FOR (SELECT * FROM (sparql define input:storage ""
            SELECT ?s ?p ?o ?g { GRAPH ?g { ?s ?p ?o } .
            FILTER (
                ?g != <http://www.openlinksw.com/schemas/virtrdf#>
                && ?g != <http://www.w3.org/ns/ldp#>
                && ?g != <http://www.w3.org/2002/07/owl#>
                && ?g != <http://localhost:8890/sparql>
                && ?g != <http://localhost:8890/DAV/>
            ) } ) AS sub OPTION (loop)) DO
    {
        IF (mod(inx, maxq) = 0) {
            result(concat('# at checkpoint  ', chckp));
            result(concat('# dump started   ', startdate));
            result(concat('# quad count     ', inx));
        }
        result(vql_create_nquad('+', "s", "p", "o", "g"));
        inx := inx + 1;

        next:;
    }
    result(concat('# at checkpoint  ', chckp));
    result(concat('# dump started   ', startdate));

    -- Datetime string in name of transaction logs has seconds resolution.
    -- Set the next checkpoint at least 1 second later than chckp.
     delay(1);
    -- See if currenttrx is stil the current transaction log.
    IF (currenttrx <> cfg_item_value(virtuoso_ini_path(), 'Database', 'TransactionFile')) {
        -- re-enable automatic checkpoints before signalling errors.
        checkpoint_interval (cpinterval);
        signal('99999', concat(': A checkpoint has been executed since start of dump at ', startdate, '. Dump invalid.'));
    }
    EXEC ('CHECKPOINT');

    -- Enable automatic checkpoints with saved interval.
    checkpoint_interval (cpinterval);

    -- See if currenttrx is free of transactions...
    rst := vql_check_trx(currenttrx);
    IF (rst[0] > 0 OR rst[1] > 0) {
        result(concat('# inserts=', rst[0], ' deletes=', rst[1]));
        signal('99999', concat(': There have been ', rst[0], ' inserts and ', rst[1], ' deletes during dump. Dump invalid.'));
    }

    -- Mark the dump as completed.
    result(concat('# dump completed ', datestring_GMT(now())));
    result(concat('# quad count     ', inx));
}
;

CREATE PROCEDURE vql_check_trx (in f VARCHAR) {
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