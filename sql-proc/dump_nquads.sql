-- See http://virtuoso.openlinksw.com/dataspace/doc/dav/wiki/Main/VirtRDFDumpNQuad

CREATE PROCEDURE dump_nquads
  ( IN  dir                VARCHAR := 'dumps'
  , IN  start_from             INT := 1
  , IN  file_length_limit  INTEGER := 100000000
  , IN  comp                   INT := 1
  )
  {
    DECLARE  inx, ses_len  INT
  ; DECLARE  file_name     VARCHAR
  ; DECLARE  env, ses      ANY
  ;

  file_mkpath(dir);

  inx := start_from;
  SET isolation = 'uncommitted';
  env := vector (0,0,0);
  ses := string_output (10000000);
  FOR (SELECT * FROM (sparql define input:storage "" SELECT ?s ?p ?o ?g { GRAPH ?g { ?s ?p ?o } . FILTER ( ?g != virtrdf: ) } ) AS sub OPTION (loop)) DO
    {
      DECLARE EXIT HANDLER FOR SQLSTATE '22023'
	{
	  GOTO next;
	};
      http_nquad (env, "s", "p", "o", "g", ses);
      ses_len := LENGTH (ses);
      IF (ses_len >= file_length_limit)
	{
	  file_name := sprintf ('%s/output%06d.nq', dir, inx);
	  string_to_file (file_name, ses, -2);
	  IF (comp)
	    {
	      gz_compress_file (file_name, file_name||'.gz');
	      file_delete (file_name);
	    }
	  inx := inx + 1;
	  env := vector (0,0,0);
	  ses := string_output (10000000);
	}
      next:;
    }
  IF (length (ses))
    {
      file_name := sprintf ('%s/output%06d.nq', dir, inx);
      string_to_file (file_name, ses, -2);
      IF (comp)
	{
	  gz_compress_file (file_name, file_name||'.gz');
	  file_delete (file_name);
	}
      inx := inx + 1;
      env := vector (0,0,0);
    }
}
;

CREATE PROCEDURE vql_dump_nquads(IN maxq INT := 100000) {
    DECLARE nquad       ANY;
    DECLARE inx INT;

    SET isolation = 'uncommitted';

    inx := 0;
    result_names (nquad);
    result(concat('# dump started ', datestring_GMT(now())));

    FOR (SELECT * FROM (sparql define input:storage ""
         	SELECT ?s ?p ?o ?g { GRAPH ?g { ?s ?p ?o } .
         	FILTER (
         		?g != virtrdf:
         		&& ?g != <http://www.w3.org/ns/ldp#>
         		&& ?g != <http://www.w3.org/2002/07/owl#>
         		&& ?g != <http://localhost:8890/sparql>
         		&& ?g != <http://localhost:8890/DAV/>
         	) } ) AS sub OPTION (loop)) DO
    {
      DECLARE EXIT HANDLER FOR SQLSTATE '22023'
	{
	  GOTO next;
	};
	  IF (mod(inx, maxq) = 0) {
	    result(concat('# dump ', inx));
	  }
      result(concat('+ ', vql_parse_trx_format_iri("s"), ' ',vql_parse_trx_format_iri("p"), ' ', vql_parse_trx_format_object("o"), ' ', vql_parse_trx_format_iri("g"), ' .'));
      inx := inx + 1;

      next:;
    }
    result(concat('# dump ended ', datestring_GMT(now())));
    EXEC ('CHECKPOINT');
}
;