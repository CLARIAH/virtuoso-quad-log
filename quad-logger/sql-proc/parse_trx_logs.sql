-- See function read_log in https://github.com/openlink/virtuoso-opensource/blob/master/libsrc/Wi/recovery.c
-- (last accessed in commit a9e42032b70280d31e48b0fed99ffe9ebd1fd124)

-- virtuoso-opensource/libsrc/Wi/log.h contains the names for the flags that are contained in line[0]

-- The following cases are handled
-- #define LOG_INSERT         1  /* prime row as DV_STRING */
-- #define LOG_KEY_INSERT    13
-- #define LOG_INSERT_REPL    8
-- #define LOG_INSERT_SOFT    9  /* prime key row follows, like insert. */
-- #define LOG_DELETE         3  /* prime key as DV_STRING */
-- #define LOG_KEY_DELETE    14

-- the following cases are ignored
-- #define LOG_UPDATE         2  /* prime key as DV_STRING, cols as DV_ARRAY_OF_LONG, value as DV_ARRAY_OF_POINTER */
-- #define LOG_COMMIT         4
-- #define LOG_ROLLBACK       5
-- #define LOG_DD_CHANGE      6
-- #define LOG_CHECKPOINT     7
-- #define LOG_TEXT          10 /* SQL string follows */
-- #define LOG_SEQUENCE      11 /* series name, count */
-- #define LOG_SEQUENCE_64   12 /* series name, count */
-- #define LOG_USER_TEXT     15 /* SQL string log'd by an user */

CREATE PROCEDURE vql_parse_trx_files(IN path VARCHAR, IN at_checkpoint VARCHAR, IN maxq INT := 100000){

    DECLARE nquad, buffer, files, trx_files ANY;
    DECLARE filename, last_log, time_stamp VARCHAR;
    DECLARE i, q_count INT;

    result_names (nquad);
    buffer := dict_new(); -- Dictionary objects are always passed by reference.
    last_log := at_checkpoint;
    q_count := 0;

    if (not ends_with(path, '/')) {
        path := concat(path, '/');
    }

    files := file_dirlist(path, 1);
    -- dbg_printf('VQL: Count of files is %d', length(files));
    trx_files := vector();
    -- Filter out non-transaction files
    for (i := 0; i < length(files); i := i + 1) {
        if (ends_with(files[i], '.trx')) {
            -- dbg_printf('VQL: Adding file %s', files[i]);
            trx_files := vector_concat(trx_files, vector(files[i]));
        }
    }

    -- dbg_printf('VQL: Count of trx files is %d', length(trx_files));
    gvector_sort(trx_files, 1, 0, 1); -- last param: nonzero for ascending sort
    -- skip the newest one, virtuoso is probably running so it will still be changing, discard logs already parsed
    for (i := 1; i < length(trx_files) - 1; i := i + 1) {
        filename := trx_files[i];
        time_stamp := regexp_match('[0-9]{14}', filename);
        if (time_stamp > at_checkpoint) {
            -- write n-quads found in file to buffer
            q_count := q_count + vql_parse_file(buffer, concat(path, filename), at_checkpoint, maxq);
            last_log := time_stamp;
            -- dbg_printf('VQL: Last log timestamp is %s', last_log);
        }
    }

    -- output the rest of the buffer
    vql_print_buffer(buffer, at_checkpoint);

    -- output timestamp of last transaction file parsed.
    result(concat('# at checkpoint ', at_checkpoint));
    result(concat('# quad count    ', q_count));
    result(concat('# last trx log  ', last_log));
}


CREATE PROCEDURE vql_parse_file(IN buffer ANY, IN file VARCHAR, IN at_checkpoint VARCHAR, IN maxq INT) {

    DECLARE handle, quad, line, lines ANY;
    DECLARE op VARCHAR;
    DECLARE pos, i, q_count INT;

    q_count := 0;
    handle := file_open (file, 0);
    while ((lines := read_log (handle, pos)) is not null) {
        quad := null;
        for (i := 0; i < length (lines); i := i + 1) {
            line := lines[i];
            if (line[0] in (1, 8, 9, 13)) {
                -- LOG_INSERT, LOG_INSERT_SOFT, LOG_INSERT_REPL and LOG_KEY_INSERT are all additions
                op := '+';
                if (line[0] = 13) {
                    -- with LOG_KEY_INSERT a flag is inserted in the line so the quad ends up in line[2] instead of line[1]
                    quad := line[2];
                } else {
                    quad := line[1];
                }
            } else if (line[0] in (3, 14)) {
                -- LOG_DELETE and LOG_KEY_DELETE are both deletions
                op := '-';
                quad := line[1];
            }
            if (quad is not null) {
                --if the operation was in one of the handled cases
                if (quad[0] = 271) {
                    -- the table DB.DBA.RDF_QUAD (id=271) is the one that's always updated. So we can ignore the others
                    -- dbg_obj_print(quad);
                    vql_buffer_nquad(op, quad[2], quad[3], quad[4], quad[1], buffer, at_checkpoint, maxq);
                    q_count := q_count + 1;
                }
            }
        }
    }
    return q_count;
}
