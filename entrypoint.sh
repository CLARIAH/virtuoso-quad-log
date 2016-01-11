#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

LOG_FILE_LOCATION=${LOG_FILE_LOCATION:-/usr/local/var/lib/virtuoso/db/virtuoso.trx}
if [ -e /storedpos ]; then
	read -r STOREDPOS < /storedpos
else
	STOREDPOS=0
fi
CURPOS=${CURPOS:-$STOREDPOS}

if [ "${1:-}" = "server" ]; then
	/usr/local/bin/virtuoso-t -f -c /usr/local/var/lib/virtuoso/db/virtuoso.ini
else
	if [ -n "${VIRTUOSO_PORT_1111_TCP_ADDR:-}" -a -n "${VIRTUOSO_PORT_1111_TCP_PORT:-}" ]; then
		ISQL_CMD="isql -H ${VIRTUOSO_PORT_1111_TCP_ADDR} -S ${VIRTUOSO_PORT_1111_TCP_PORT} -u ${VIRTUOSO_USER:-dba} -p ${VIRTUOSO_PASSWORD:-dba}"
	else
		ISQL_CMD="isql -H $VIRTUOSO_ISQL_ADDRESS -S $VIRTUOSO_ISQL_PORT -u ${VIRTUOSO_USER:-dba} -p ${VIRTUOSO_PASSWORD:-dba}"
	fi

	set +o errexit
	$ISQL_CMD <<-'EOF' | grep -q 'parse_trx'
		SET CSV=ON;
		SELECT P_NAME FROM SYS_PROCEDURES WHERE P_NAME = 'DB.DBA.parse_trx';
		exit;
		EOF
	GREPRESULT=${PIPESTATUS[1]}
	set -o errexit
	if [ $GREPRESULT -ne 0 ]; then
		read -p "To read the transaction log from the server I need to install the stored procedure 'parse_trx'. Is that okay? [yn]" insert_procedure
		if [ "$insert_procedure" != "y" ]; then
			echo "Without the stored procedure I can't be of much use. Sorry."
			exit 1
		else
			echo "Inserting stored procedure:"
			$ISQL_CMD < parse_trx.sql
			echo "done. Rerun me for a grab run."
			exit 0
		fi
	fi
	$ISQL_CMD > output <<-EOF
		SET CSV=ON;
		parse_trx('$LOG_FILE_LOCATION', $CURPOS);
		exit;
	EOF
	cat output | grep ELDS_OUTPUT | cut -s -d' ' -f 2- | sed 's|<nodeid://b\([^>]+\)|_:b\1|g' #sed command translates from internal blank node format to standardised format
	cat output | grep -o '# CURRENT_POSITION \+[0-9]\+' | grep -o '[0-9]\+' > /storedpos
fi
