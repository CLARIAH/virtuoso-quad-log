#!/usr/bin/env bash
set -o nounset
set -o errexit

LOG_FILE_LOCATION=${LOG_FILE_LOCATION:-/usr/local/var/lib/virtuoso/db}

if [ -n "${VIRTUOSO_PORT_1111_TCP_ADDR:-}" -a -n "${VIRTUOSO_PORT_1111_TCP_PORT:-}" ]; then
	ISQL_CMD="isql -H ${VIRTUOSO_PORT_1111_TCP_ADDR} -S ${VIRTUOSO_PORT_1111_TCP_PORT} -u ${VIRTUOSO_USER:-dba} -p ${VIRTUOSO_PASSWORD:-dba}"
else
	ISQL_CMD="isql -H $VIRTUOSO_ISQL_ADDRESS -S $VIRTUOSO_ISQL_PORT -u ${VIRTUOSO_USER:-dba} -p ${VIRTUOSO_PASSWORD:-dba}"
fi

$ISQL_CMD <<-'EOF' > parse_trx_query_result.txt
	SET CSV=ON;
	SELECT P_NAME FROM SYS_PROCEDURES WHERE P_NAME = 'DB.DBA.parse_trx';
	exit;
	EOF

if ! grep -q 'parse_trx' parse_trx_query_result.txt; then
	if [ -z "${INSERT_PROCEDURE:-}" ]; then
		read -p "To read the transaction log from the server I need to install a few stored procedures on the virtuoso server. All starting with 'parse_trx'. Is that okay? [yn]" INSERT_PROCEDURE
	fi
	if [ "$INSERT_PROCEDURE" != "y" ]; then
		echo "Without the stored procedure I can't be of much use. Sorry. You might want to run me connected to a dummy virtuoso server in a container as detailed in the README." >&2
		exit 1
	else
		echo "Inserting stored procedure:" >&2
		$ISQL_CMD < parse_trx.sql
	fi
fi
mkdir -p datadir
cd datadir

#get the latest log
latestlogsuffix=`ls rdfpatch-* | sort -r | head -n 1 | sed 's/^rdfpatch-//' || ''`

# parse_trx_files to marked output file
mark=$(date +"%Y%m%d%H%M%S")
output="output$mark"

errorfile=isql.errors
if [ -e "$errorfile" ]; then
	rm "$errorfile"
fi

$ISQL_CMD 2>$errorfile > "$output" <<-EOF
	parse_trx_files('$LOG_FILE_LOCATION', '$latestlogsuffix');
	exit;
EOF

# capture errors from isql:
if grep -q "\*\*\* Error [0-9]\{5\}: \[Virtuoso Driver\]\[Virtuoso Server\]" "$errorfile"; then
	echo "Received error from isql @ $VIRTUOSO_ISQL_ADDRESS:$VIRTUOSO_ISQL_PORT"
	echo "$(cat -n $errorfile)"
	exit 1
fi

# split output to marked files; use more than standard 2 digits for split file suffix
prefix='xyx'$mark'_'
csplit -f "$prefix" -n 4 -s "$output" "/^# start: /" '{*}'
#loop over all files
for file in $prefix*; do
	if [ `wc -l $file | grep -o '^[0-9]\+'` -gt 1 ]; then # first line is the header, so a one-line file is effectively empty
				 # line with the filename, just the filename,		        remove .trx and trailing spaces, keep only the 14 digits at then end (not y10k proof)
		timestamp=`head -n1 $file        | sed 's|^# start:.*/\(.*\)|\1|' | sed 's/\.trx *$//'             | grep -o '[0-9]\{14\}$' || echo ''`
		if [ -n "$timestamp" ]; then
			echo "generated rdfpatch-${timestamp}" >&2
			cp $file "rdfpatch-${timestamp}"
		fi
	fi
	rm $file
done
rm "$output"
cd ..

if [ -z "${HTTP_SERVER_URL:-}" ]; then
	if [ -n "${HTTP_SERVER_PORT_80_TCP_ADDR:-}" ]; then
		HTTP_SERVER_URL="http://${HTTP_SERVER_PORT_80_TCP_ADDR}:${HTTP_SERVER_PORT_80_TCP_PORT}"
	else
		HTTP_SERVER_URL="http://example.org/"
	fi
fi

./resource-list.py --resource-url "${HTTP_SERVER_URL}" --resource-dir "$PWD/datadir"

if [ -n "${CUR_USER:-}" ]; then
	chown -R "$CUR_USER:$CUR_USER" datadir
fi

exit 0
