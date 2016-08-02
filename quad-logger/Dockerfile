FROM encoflife/virtuoso:7.2.0

#virtuoso image is used for the client binary

COPY sql-proc/ /sql-proc/
COPY entrypoint.sh /
COPY generate-rdfpatch.sh /

RUN mkdir /datadir

ENTRYPOINT ["/entrypoint.sh"]
