#!/usr/bin/env bash
set -o nounset
set -o errexit

# The location of transaction logs on the Virtuoso server.
LOG_FILE_LOCATION=${LOG_FILE_LOCATION:-/usr/local/var/lib/virtuoso/db}

# Remote isql command
ISQL_CMD="isql -H $VIRTUOSO_ISQL_ADDRESS -S $VIRTUOSO_ISQL_PORT -u ${VIRTUOSO_USER:-dba} -p ${VIRTUOSO_PASSWORD:-dba}"

# File to report isql errors
ISQL_ERROR_FILE=isql.errors
if [ -e "$ISQL_ERROR_FILE" ]; then
	rm "$ISQL_ERROR_FILE"
fi

###############################
# assert_no_isql_error
# Assert no error is reported to the isql error file.
#
# Globals:      ISQL_ERROR_FILE, VIRTUOSO_ISQL_ADDRESS, VIRTUOSO_ISQL_PORT
# Arguments:    None
# Returns:      None
# Exit status:  1 on error found.
assert_no_isql_error()
{
	if grep -q "\*\*\* Error [0-9]\{5\}: \[Virtuoso Driver\]\[Virtuoso Server\]" "$ISQL_ERROR_FILE"; then
		echo "Received error from isql @ $VIRTUOSO_ISQL_ADDRESS:$VIRTUOSO_ISQL_PORT" >&2
		echo "$(cat -n $ISQL_ERROR_FILE)" >&2
		exit 1
	fi
}

###############################
# assert_procedures_stored
# Assert that stored procedures are available on the Virtuoso server; insert them if needed.
#
# Globals:      INSERT_PROCEDURES, ISQL_ERROR_FILE
# Arguments:    None 'balala'
# Returns:      None
# Exit status:  1 if procedures cannot be inserted.
assert_procedures_stored()
{
	files=(parse_trx.sql dump_nquads.sql)
	procedures_count=5

	$ISQL_CMD <<-'EOF' > query_result 2>$ISQL_ERROR_FILE
		SET CSV=ON;
		SELECT P_NAME FROM SYS_PROCEDURES WHERE P_NAME LIKE 'DB.DBA.vql_*';
		exit;
		EOF
	assert_no_isql_error

    # cannot use   found_procedures=$(grep -c 'DB\.DBA\.vql_' query_result)   in combination with   set -o errexit
	found_procedures=$(grep -o "DB\.DBA\.vql_*" query_result | wc -l)
	echo "Found $found_procedures out of $procedures_count required stored procedures." >&2

	if [ "$found_procedures" != "$procedures_count" ] ; then
		if [ -z "${INSERT_PROCEDURES:-}" ]; then
			read -p "To dump quads and read transaction logs from the server I need to install a few stored procedures \
			on the virtuoso server. Is that okay? [yn]" INSERT_PROCEDURES
		fi
		if [ "$INSERT_PROCEDURES" != "y" ]; then
			echo "Without the stored procedures I can't be of much use. Sorry. You might want to run me connected to \
			a dummy virtuoso server in a container as detailed in the README." >&2
			exit 1
		else
			echo "Inserting stored procedures..." >&2
			for file in "${files[@]}"
			do
				$ISQL_CMD < "sql-proc/$file" > /dev/null 2>$ISQL_ERROR_FILE
				assert_no_isql_error
				echo "Inserted sql-proc/$file" >&2
			done
		fi
	fi
	rm query_result
}

assert_dump_at_checkpoint()
{
    echo "allee"
}

# Assert that stored procedures are available on the Virtuoso server; insert them if needed.
assert_procedures_stored

# Create the data directory, change to it.
#mkdir -p datadir
cd datadir


assert_dump_at_checkpoint
	


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
	vql_parse_trx_files('$LOG_FILE_LOCATION', '$latestlogsuffix');
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
