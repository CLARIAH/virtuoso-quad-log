FROM encoflife/virtuoso:7.2.0

COPY entrypoint.sh /entrypoint.sh
COPY parse_trx.sql /parse_trx.sql
COPY virtuoso.ini /usr/local/var/lib/virtuoso/db/virtuoso.ini

ENTRYPOINT ["/entrypoint.sh"]
