#!/usr/bin/env bash
set -o nounset
set -o errexit

# Keep indented with tabs instead of spaces because of heredocs (EOF).

# The Virtuoso user.
VIRTUOSO_USER=${VIRTUOSO_USER:-dba}

# The location of transaction logs on the Virtuoso server.
LOG_FILE_LOCATION=${LOG_FILE_LOCATION:-/usr/local/var/lib/virtuoso/db}

INSERT_PROCEDURES=${INSERT_PROCEDURES:-y}

# Should we dump the initial state of the quad store.
DUMP_INITIAL_STATE=${DUMP_INITIAL_STATE:-y}

# Maximum amount of quads per dump file.
MAX_QUADS_IN_DUMP_FILE=${MAX_QUADS_IN_DUMP_FILE:-100000}

# Should we dump the current state of the quad store and then exit.
DUMP_AND_EXIT=${DUMP_AND_EXIT:-n}

DEFAULT_EXCLUDED_GRAPHS="http://www.openlinksw.com/schemas/virtrdf# \
http://www.w3.org/ns/ldp# \
http://www.w3.org/2002/07/owl# \
http://localhost:8890/sparql \
http://localhost:8890/DAV/"

EXCLUDED_GRAPHS=${EXCLUDED_GRAPHS:-$DEFAULT_EXCLUDED_GRAPHS}

# Connection to the Virtuoso server. See also:
# https://docs.docker.com/engine/userguide/networking/default_network/dockerlinks/
# https://docs.docker.com/engine/userguide/networking/work-with-networks/#linking-containers-in-user-defined-networks
if [ -n "${VIRTUOSO_SERVER_HOST_NAME:-}" -a -n "${VIRTUOSO_SERVER_ISQL_PORT:-}" ]; then
    # Started under a docker user defined network or within a 'traditional' network
    ISQL_SERVER="isql -H ${VIRTUOSO_SERVER_HOST_NAME} -S ${VIRTUOSO_SERVER_ISQL_PORT}"
elif [ -n "${VIRTUOSO_PORT_1111_TCP_ADDR:-}" -a -n "${VIRTUOSO_PORT_1111_TCP_PORT:-}" ]; then
    # Started under legacy docker bridge with --link
	ISQL_SERVER="isql -H ${VIRTUOSO_PORT_1111_TCP_ADDR} -S ${VIRTUOSO_PORT_1111_TCP_PORT}"
else
    ISQL_SERVER="isql -H ${VIRTUOSO_SERVER_HOST_NAME:-192.168.99.100} -S ${VIRTUOSO_SERVER_ISQL_PORT:-1111}"
fi
ISQL_CMD="$ISQL_SERVER -u ${VIRTUOSO_USER:-dba} -p ${VIRTUOSO_PASSWORD:-dba}"

CURRENT_DIR=$PWD

# Directory used for serving Resource Sync files. Should be mounted on the host.
DATA_DIR=$(echo "$CURRENT_DIR" | sed 's/^\/$//')/datadir
mkdir -p $DATA_DIR

# File to report isql errors
ISQL_ERROR_FILE=$(echo "$CURRENT_DIR" | sed 's/^\/$//')/isql.errors
if [ -e "$ISQL_ERROR_FILE" ]; then
	rm "$ISQL_ERROR_FILE"
fi

##########################################################
## FUNCTIONS #############################################

###############################
# test_connection
# Call the ISQL_CMD.
#
# Globals:      ISQL_CMD
# Arguments:    None
# Returns:      None
test_connection() {
	$ISQL_CMD <<-EOF 2>$ISQL_ERROR_FILE > dev/null
		exit;
		EOF
}

###############################
# assert_no_isql_error
# Assert no error is reported to the isql error file.
#
# Globals:      ISQL_ERROR_FILE, ISQL_SERVER
# Arguments:    None
# Returns:      None
# Exit status:  1 on error found.
assert_no_isql_error()
{
	if grep -q "\*\*\* Error [A-Z0-9]\{5\}: \[Virtuoso Driver\]\[Virtuoso Server\]" "$ISQL_ERROR_FILE"; then
		echo "Received error from $ISQL_SERVER" >&2
		echo "$(cat -n $ISQL_ERROR_FILE)" >&2
		exit 1
	fi
}

###############################
# assert_procedures_stored
# Assert that stored procedures are available on the Virtuoso server; insert them if needed.
#
# Globals:      INSERT_PROCEDURES, ISQL_ERROR_FILE
# Environment:  Procedure files are in the directory 'sql-proc', relative to current directory.
# Arguments:    None
# Returns:      None
# Exit status:  1 if procedures are not stored and cannot be inserted.
assert_procedures_stored()
{
	# files are in the directory 'sql-proc'
	local files=(utils.sql dump_nquads.sql  parse_trx.sql)
	# the number of procedures that start with 'vql_*'
	local procedures_count=8

	$ISQL_CMD <<-'EOF' > query_result 2>$ISQL_ERROR_FILE
		SET CSV=ON;
		SELECT COUNT(*) FROM SYS_PROCEDURES WHERE P_NAME LIKE 'DB.DBA.vql_*';
		exit;
		EOF
	assert_no_isql_error

	local found_procedures=$(grep "^[0-9]*$" query_result)

	if [ "$found_procedures" != "$procedures_count" ] ; then
		echo "Found $found_procedures out of $procedures_count required stored procedures." >&2
		if [ "$INSERT_PROCEDURES" != "y" ]; then
			read -p "To dump quads and read transaction logs from the server I need to install a few stored procedures on the virtuoso server. Is that okay? [yn] " INSERT_PROCEDURES
		fi
		if [ "$INSERT_PROCEDURES" != "y" ]; then
			echo "Without the stored procedures I can't be of much use. Sorry. You might want to run me connected to a dummy virtuoso server in a container as detailed in the README." >&2
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

###############################
# assert_virtuoso_configuration
# Assert that the Virtuoso server is configured as we expect.
#
# Globals:      None
# Arguments:    None
assert_virtuoso_configuration()
{
	$ISQL_CMD <<-'EOF' > query_result 2>$ISQL_ERROR_FILE
		vql_assert_configuration();
		exit;
		EOF
	assert_no_isql_error
}

###############################
# assert_dump_completed_normal
# Assert that an existing dump completed normal.
#
# Globals:      DATA_DIR
# Arguments:    None
# Returns:      Name of the last file in the dump.
# Exit status:  1 if dump did not complete normally.
assert_dump_completed_normal()
{
	local lastfile=$(ls $DATA_DIR/rdfdump-* | sort -r | head -n 1)
	completed=$(cat $lastfile | { grep "# dump completed " || true; } )
	if [ "$completed" = "" ] ; then
		echo "DUMP ERROR: Dump did not complete normally." >&2
		exit 1
	fi
	echo "$lastfile"
}

###############################
# dump_nquads
# Call vql_dump_nquads on server.
#
# Globals:      MAX_QUADS_IN_DUMP_FILE
# Arguments:    None
# Returns:      dump stream on &1, can be picked up with -
dump_nquads()
{
	$ISQL_CMD <<-EOF 2>$ISQL_ERROR_FILE
		vql_dump_nquads($MAX_QUADS_IN_DUMP_FILE, '$EXCLUDED_GRAPHS');
		exit;
		EOF
}

###############################
# execute_dump
# Dump all quads on the server to rdf-patch-formatted files.
#
# Globals:      DATA_DIR
# Arguments:    None
# Returns:      None
execute_dump()
{
	echo "Executing dump..." >&2
	dump_nquads | grep "^#\|^\+" | csplit -f "$DATA_DIR/rdfdump-" -n 5 -s - "/^# at checkpoint  /" {*}
	assert_no_isql_error
	local lastfile=$(assert_dump_completed_normal)

	# first file is empty
	rm "$DATA_DIR/rdfdump-00000"

	# The last file only contains information on the dump. Keep it as a mark.
	# Also set the last file as latestlogsuffix marker
	local checkpoint=$(cat $lastfile | grep "# at checkpoint" | sed -e s/[^0-9]//g)
	cp "$lastfile" "$DATA_DIR/rdfpatch-$checkpoint"

	# report
	echo "Dump reported in '$lastfile'" >&2
	echo "$(cat $lastfile)" >&2
}

###############################
# dump_if_needed
# Check if an initial dump has to be made and execute dump if needed.
#
# Globals:      DUMP_INITIAL_STATE, DATA_DIR
# Arguments:    None
# Returns:      None
# Exit status:  1 if dump did not complete normally.
#               255 if dump-and-exit was requested.
dump_if_needed()
{
	if [ "$DUMP_INITIAL_STATE" = "y" ]; then
		if [ ! -e "$DATA_DIR/rdfdump-00001" ]; then
		    if ls "$DATA_DIR/rdfpatch-"* 1> /dev/null 2>&1; then
		        echo "'rdfpatch-*' files found in '$DATA_DIR'. Remove them before dumping."
		        exit 1
		    elif ls "$DATA_DIR/rdfdump-"* 1> /dev/null 2>&1; then
		        echo "'rdfdump-*' files found in '$DATA_DIR'. Remove them before dumping."
		        exit 1
		    else
			    execute_dump
			fi
		else
			assert_dump_completed_normal > dev/null
		fi
	else
		echo "Not checking dump status because DUMP_INITIAL_STATE is not 'y'" >&2
	fi

	# Quit, in case dump-and-exit was requested.
	if [ "$DUMP_AND_EXIT" = "y" ]; then
		echo "Exiting the Virtuoso quad logger because DUMP_AND_EXIT is 'y'" >&2
		exit 255
	fi
}

###############################
# sync_transaction_logs
# Parse newly found transaction logs to rdf patch files.
#
# Globals:      DATA_DIR, CURRENT_DIR
# Arguments:    None
# Returns:      None
sync_transaction_logs()
{
	#get the latest log suffix
	cd ${DATA_DIR}
	local latestlogsuffix=`ls rdfpatch-* | sort -r | head -n 1 | sed 's/^rdfpatch-//' || ''`
	cd ${CURRENT_DIR}
	echo "Syncing transaction logs starting from $latestlogsuffix" >&2

	# parse_trx_files to marked output file
	local mark=$(date +"%Y%m%d%H%M%S")
	local output="$DATA_DIR/output$mark"

	$ISQL_CMD 2>$ISQL_ERROR_FILE > "$output" <<-EOF
		vql_parse_trx_files('$LOG_FILE_LOCATION', '$latestlogsuffix');
		exit;
	EOF
	assert_no_isql_error

	# split output to marked files; use more than standard 2 digits for file suffix
	local prefix='xyx'$mark'_'
	csplit -f "$DATA_DIR/$prefix" -n 4 -s "$output" "/^# start: /" '{*}'
	#loop over all files
	local file
	for file in $DATA_DIR/$prefix*; do
		# first line is the header, so a one-line file is effectively empty
		if [ `wc -l $file | grep -o '^[0-9]\+'` -gt 1 ]; then
			# line with the filename,   just the filename, remove .trx and trailing spaces, keep only the 14 digits at then end (not y10k proof)
			local timestamp=`head -n1 $file | sed 's|^# start:.*/\(.*\)|\1|' | sed 's/\.trx *$//' | grep -o '[0-9]\{14\}$' || echo ''`
			if [ -n "$timestamp" ]; then
				if [[ ! "$latestlogsuffix" < "$timestamp" ]]; then
					echo -e "Timestamp on parsed transaction log is smaller than or equal to recorded latest log suffix:" \
						"\n\t$timestamp <= $latestlogsuffix" \
						"\n\tServer transaction logs and recorded rdf-patch files are not in line. We quit." >&2
					rm "$DATA_DIR/$prefix"*
					rm "$output"
					exit 1
				fi
				echo "generated rdfpatch-${timestamp}" >&2
				cp $file "$DATA_DIR/rdfpatch-${timestamp}"
			fi
		fi
		rm $file
	done
	rm "$output"
}

##########################################################
## PROGRAM FLOW ##########################################

test_connection && echo "Connected to $ISQL_SERVER" || echo "No connection to $ISQL_SERVER" >&2

# Assert that stored procedures are available on the Virtuoso server; insert them if needed.
assert_procedures_stored

# Assert that the Virtuoso server is configured as we expect.
assert_virtuoso_configuration

# Check if an initial dump has to be made and execute dump if needed.
dump_if_needed

# Parse newly found transaction logs to rdf patch files.
sync_transaction_logs


# https://docs.docker.com/engine/userguide/networking/default_network/dockerlinks/
# https://docs.docker.com/engine/userguide/networking/work-with-networks/#linking-containers-in-user-defined-networks
# @Could do: Move Resource Sync functionality to another Docker container
if [ -z "${HTTP_SERVER_URL:-}" ]; then
	if [ -n "${HTTP_SERVER_PORT_80_TCP_ADDR:-}" ]; then
		HTTP_SERVER_URL="http://${HTTP_SERVER_PORT_80_TCP_ADDR}:${HTTP_SERVER_PORT_80_TCP_PORT}"
	else
		HTTP_SERVER_URL="http://example.org/"
	fi
fi

./resource-list.py --resource-url "${HTTP_SERVER_URL}" --resource-dir "$DATA_DIR"

if [ -n "${CUR_USER:-}" ]; then
	chown -R "$CUR_USER:$CUR_USER" "$DATA_DIR"
fi

exit 0
