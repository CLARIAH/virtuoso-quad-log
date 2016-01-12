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

create procedure parse_trx (in f any, in inpos int := 0)
{
  declare grepmarker, h, op, indexOrSomething, g, s, p, o any;
  declare pos int;
  result_names (grepmarker, op, s, p, o, g, indexOrSomething);
  h := file_open (f, inpos);
  declare line, lines any;
  while ((lines := read_log (h, pos)) is not null)
  {
    declare quad any;
    declare i int;
    quad := null;
    for (i := 1; i < length (lines); i := i + 1)
    {

      line := lines[i];
      if (line[0] in (1,8,9,13)) -- LOG_INSERT, LOG_INSERT_SOFT, LOG_INSERT_REPL and LOG_KEY_INSERT are all additions
      {
        op := 'A';
        if (line[0] = 13)
        {
          quad := line[2]; -- with LOG_KEY_INSERT a flag is inserted in the line so the quad ends up in line[2] instead of line[1]
        }
        else
        {
          quad := line[1];
        }
      }
      else if (line[0] in (3,14)) -- LOG_DELETE and LOG_KEY_DELETE are both deletions
      {
        op := 'D';
        quad := line[1];
      }

      if (quad is not null) --if the operation was in one of the handled cases
      {
        if (quad[0] = 271) {
          --There are a few tables and indexes that store the quads (select * from SYS_KEYS WHERE KEY_NAME like '%QUAD%')
          --according to the read_log example in the virtuoso documentation it seems that the table DB.DBA.RDF_QUAD (id=271)
          --is the one that's always updated. So we can ignore the others
          result ('parse_trx_OUTPUT', op, __ro2sq (quad[2]), __ro2sq (quad[3]), __ro2sq (quad[4]), __ro2sq (quad[1]), __ro2sq(quad[0]));
        }
      }
    }
  }
  result ('parse_trx_OUTPUT', '# CURRENT_POSITION', pos + inpos, ' ', ' ', ' ', ' ');
}
;
