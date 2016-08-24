FROM encoflife/virtuoso:7.2.0

COPY wordnet-subset.nt /usr/local/var/lib/virtuoso/db/wordnet-subset.nt
COPY special-chars.nt /usr/local/var/lib/virtuoso/db/special-chars.nt
COPY continents.rdf /usr/local/var/lib/virtuoso/db/continents.rdf
COPY agricultureProducts.xml /usr/local/var/lib/virtuoso/db/agricultureProducts.xml
COPY virtuoso.ini /usr/local/var/lib/virtuoso/db/virtuoso.ini

RUN virtuoso-t +wait +configfile /usr/local/var/lib/virtuoso/db/virtuoso.ini && \
  ls /usr/local/var/lib/virtuoso/db/ && \
  isql 1111 dba dba exec="ld_add('/usr/local/var/lib/virtuoso/db/wordnet-subset.nt', 'http://example.com/clariah'); \
    ld_add('/usr/local/var/lib/virtuoso/db/special-chars.nt', 'info:special'); \
    ld_add('/usr/local/var/lib/virtuoso/db/continents.rdf', 'http://www.telegraphis.net/ontology/geography/geography#'); \
    ld_add('/usr/local/var/lib/virtuoso/db/agricultureProducts.xml', 'http://www.daml.org/2001/12/factbook/agricultureProducts'); \
    rdf_loader_run(NULL, 3); \
    delay(5); \
    shutdown;" && \
  rm /usr/local/var/lib/virtuoso/db/wordnet-subset.nt && \
  rm /usr/local/var/lib/virtuoso/db/special-chars.nt && \
  rm /usr/local/var/lib/virtuoso/db/continents.rdf && \
  rm /usr/local/var/lib/virtuoso/db/agricultureProducts.xml && \
  ls /usr/local/var/lib/virtuoso/db/

CMD ["/usr/local/bin/virtuoso-t", "-f", "-c", "/usr/local/var/lib/virtuoso/db/virtuoso.ini"]
