FROM encoflife/virtuoso:7.2.0

COPY wordnet-subset.nt /usr/local/var/lib/virtuoso/db/wordnet-subset.nt
COPY virtuoso.ini /usr/local/var/lib/virtuoso/db/virtuoso.ini

RUN virtuoso-t +wait +configfile /usr/local/var/lib/virtuoso/db/virtuoso.ini && \
  ls /usr/local/var/lib/virtuoso/db/ && \
  isql 1111 dba dba exec="DB.DBA.TTLP_MT(file_to_string_output('/usr/local/var/lib/virtuoso/db/wordnet-subset.nt'), '', 'http://example.com/clariah', 2); SPARQL WITH <http://example.com/clariah> DELETE { ?s ?p ?v } WHERE { ?s <http://wordnet-rdf.princeton.edu/ontology#tag_count> ?o . FILTER ( ?o = \"0\"^^<http://www.w3.org/2001/XMLSchema#integer> ) ?s ?p ?v }; checkpoint" && \
  isql 1111 dba dba -K && \
  ls /usr/local/var/lib/virtuoso/db/


CMD ["/usr/local/bin/virtuoso-t", "-f", "-c", "/usr/local/var/lib/virtuoso/db/virtuoso.ini"]
