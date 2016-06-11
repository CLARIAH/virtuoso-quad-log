-- See also http://virtuoso.openlinksw.com/dataspace/doc/dav/wiki/Main/VirtRDFDumpNQuad

CREATE PROCEDURE vql_dump_nquads(IN maxq INT := 100000) {

    DECLARE nquad, chckp, date2, startdate ANY;
    DECLARE inx, cpc                       INT;

    SET isolation = 'serializable';

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

    IF (chckp <> date2) {
        -- This will/should/could never happen?
        signal('99999', 'Could not get unequivocal checkpoint. Try again some other time.');
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
    result(concat('# dump completed ', datestring_GMT(now())));
    result(concat('# quad count     ', inx));

    -- Datetime string in name of transaction logs has second resolution.
    -- Set the next checkpoint at least 1 second later than chckp.
    delay(1);
    EXEC ('CHECKPOINT');
}
;