#!/usr/bin/env bash
set -o nounset
set -o errexit

# Keep indented with tabs instead of spaces because of heredocs (EOF).

# The location of transaction logs on the Virtuoso server.
LOG_FILE_LOCATION=${LOG_FILE_LOCATION:-/usr/local/var/lib/virtuoso/db}

INSERT_PROCEDURES=${INSERT_PROCEDURES:-n}

# Should we dump the initial state of the quad store.
DUMP_INITIAL_STATE=${DUMP_INITIAL_STATE:-y}

# Maximum amount of quads per file. (100.000 quads ~ 12,5 MB)
MAX_QUADS_PER_FILE=${MAX_QUADS_PER_FILE:-100000}

# Should we dump the current state of the quad store and then exit.
DUMP_AND_EXIT=${DUMP_AND_EXIT:-n}

DEFAULT_EXCLUDED_GRAPHS="http://www.openlinksw.com/schemas/virtrdf# \
http://www.w3.org/ns/ldp# \
http://www.w3.org/2002/07/owl# \
http://localhost:8890/sparql \
http://localhost:8890/DAV/"

# Graphs that are excluded from the initial dump. Space-separated list of iri's.
EXCLUDED_GRAPHS=${EXCLUDED_GRAPHS:-$DEFAULT_EXCLUDED_GRAPHS}

# Connection to the Virtuoso server ISQL interface
ISQL_SERVER="isql -H ${VIRTUOSO_HOST_NAME} -S ${VIRTUOSO_ISQL_PORT:-1111}"
ISQL_CMD="$ISQL_SERVER -u ${VIRTUOSO_DB_USER:-dba} -p ${VIRTUOSO_DB_PASSWORD:-dba}"

# Directory used for dumping rdf-patch files.
DUMP_DIR="${DUMP_DIR:-/output}"
mkdir -p "$DUMP_DIR"

# File to report isql errors
ISQL_ERROR_FILE="$DUMP_DIR/isql.errors"
if [ -e "$ISQL_ERROR_FILE" ]; then
	rm "$ISQL_ERROR_FILE"
fi

# File for keeping last log suffix.
LAST_LOG_SUFFIX="$DUMP_DIR/vql_lastlogsuffix.txt"

# File signalling stored procedures are up to date.
MD5_STORED_PROCEDURES=md5_stored_procedures

# File constituting handshake between this service and chained services.
STARTED_AT_FILE="$DUMP_DIR/vql_started_at.txt"

# File enabling processing of last real 'rdf_out_*' file by chained processes
SHAM_RDF_OUT_FILE="$DUMP_DIR/rdf_out_99999999999999-99999999999999"

# File with dump information, also used to check if a successful dump has been executed.
DUMP_INFO_FILE="$DUMP_DIR/vql_rdfdump_info.txt"

# File with total number exported nquads thus far.
COUNT_NQUADS_FILE="$DUMP_DIR/vql_nquads_count.txt"

# File with total number exported files thus far.
COUNT_NFILES_FILE="$DUMP_DIR/vql_files_count.txt"

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
	$ISQL_CMD <<-EOF 2>$ISQL_ERROR_FILE > /dev/null
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
# write_md5_stored_procedures
# Write the md5 hash of stored procedures to the file md5_stored_procedures. The file md5_stored_procedures
# signals that latest version of stored procedures have been inserted.
#
# Globals:      ISQL_CMD, ISQL_ERROR_FILE, MD5_STORED_PROCEDURES
# Arguments:    None
# Returns:      None
write_md5_stored_procedures()
{
	$ISQL_CMD <<-'EOF' 2>$ISQL_ERROR_FILE | grep "^DB\.DBA\." > "$MD5_STORED_PROCEDURES"
		SELECT P_NAME, md5(concat(P_TEXT, P_MORE)) FROM SYS_PROCEDURES WHERE P_NAME LIKE 'DB.DBA.vql_*';
		exit;
		EOF
	assert_no_isql_error
}

###############################
# assert_procedures_stored
# Assert that stored procedures are available on the Virtuoso server; insert them if needed.
#
# Globals:      INSERT_PROCEDURES, ISQL_CMD, ISQL_ERROR_FILE, MD5_STORED_PROCEDURES
# Environment:  Procedure files are in the directory 'sql-proc', relative to current directory.
# Arguments:    None
# Returns:      None
# Exit status:  1 if procedures are not stored and cannot be inserted.
assert_procedures_stored()
{
	# files are in the directory 'sql-proc'
	local files=(utils.sql dump_nquads.sql parse_trx_logs.sql split_nquads.sql)
	# the number of procedures that start with 'vql_*'
	local procedures_count=12

	$ISQL_CMD <<-'EOF' > query_result 2>$ISQL_ERROR_FILE
		SET CSV=ON;
		SELECT COUNT(*) FROM SYS_PROCEDURES WHERE P_NAME LIKE 'DB.DBA.vql_*';
		exit;
		EOF
	assert_no_isql_error

	local found_procedures=$(grep "^[0-9]*$" query_result)

	if [ "$found_procedures" != "$procedures_count" ] || [ ! -e "$MD5_STORED_PROCEDURES" ]; then
		echo "Found $found_procedures out of $procedures_count required stored procedures." >&2
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
			write_md5_stored_procedures
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
# Globals:      None
# Arguments:    path: path and filename of the file with dump information.
# Returns:      None
# Exit status:  1 if dump did not complete normally.
assert_dump_completed_normal()
{
    local path="$1"
	completed=$(cat $path | { grep "# dump completed " || true; } )
	if [ "$completed" = "" ] ; then
		echo "DUMP ERROR: Dump did not complete normally." >&2
		exit 1
	fi
}

###############################
# dump_nquads
# Call vql_dump_nquads on server.
#
# Globals:      MAX_QUADS_PER_FILE, EXCLUDED_GRAPHS
# Arguments:    None
# Returns:      dump stream on &1, can be picked up with -
dump_nquads()
{
	$ISQL_CMD <<-EOF 2>$ISQL_ERROR_FILE
		vql_dump_nquads($MAX_QUADS_PER_FILE, '$EXCLUDED_GRAPHS');
		exit;
		EOF
}

###############################
# execute_dump
# Dump all quads on the server to rdf-patch-formatted files in the directory DUMP_DIR with the name pattern
# 'rdfpatch-0dxxxxxxxxxxxx', where 'xxxxxxxxxxxx' is a 12 digit serial number.
# In order to make sure new data is only updated
# atomically and will never contain half a dump synchronic processes should not work with the last file with a
# name pattern 'rdfpatch-*'. This method will create a badger file with the name 'rdfpatch-99999999999999'
# when finished, thus enabling the processing of the last real 'rdfpatch-*' file.
# This method writes the timestamp of the for last transaction log to the file LAST_LOG_SUFFIX.
#
# Globals:      DUMP_DIR, LAST_LOG_SUFFIX
# Arguments:    None
# Returns:      None
execute_dump()
{
	echo "Executing dump..." >&2
	printf $(date +"%Y%m%d%H%M%S") > "$STARTED_AT_FILE"

    local output="$DUMP_DIR/rdf_out_00000000000000-"
	dump_nquads | grep "^#\|^\+" | csplit -f "$output" -n 14 -sz - "/^# at checkpoint  /" {*}
	assert_no_isql_error
	local lastfile=$(ls "$output"* | sort -r | head -n 1)
	if [[ -z "${lastfile// }" ]]; then
        echo "Error: execute_dump ended abnormal." >&2
        exit 1
	fi
	assert_dump_completed_normal "$lastfile"

	# The last file only contains information on the dump.
	local checkpoint=$(cat $lastfile | grep "# at checkpoint" | sed -e s/[^0-9]//g)
	local nquads=$(cat $lastfile | grep "# quad count" | sed -e s/[^0-9]//g)
	local nfiles=$(cat $lastfile | grep "# file count" | sed -e s/[^0-9]//g)

	# Set the marker file to mark dump has completed
	mv "$lastfile" "$DUMP_INFO_FILE"

	# Write checkpoint as lastlogsuffix in dedicated file.
	printf "$checkpoint" > "$LAST_LOG_SUFFIX"

	# Keep track of the number of exported N-Quads
	printf "$nquads" > "$COUNT_NQUADS_FILE"

	# Keep track of the number of exported files
	printf "$nfiles" > "$COUNT_NFILES_FILE"

	# Processes in chain will not consider last file (in alphabetical sort order) with pattern rdf_out_*.
	# Enable processing of last dump file by creating an extra file.
	touch "$SHAM_RDF_OUT_FILE"

	# report
	echo "Dump reported in '$DUMP_INFO_FILE'" >&2
	echo "$(cat $DUMP_INFO_FILE)" >&2
}

###############################
# dump_if_needed
# Check if an initial dump has to be made and execute dump if needed.
#
# Globals:      DUMP_INITIAL_STATE, DUMP_DIR
# Arguments:    None
# Returns:      None
# Exit status:  1 if dump did not complete normally.
#               255 if dump-and-exit was requested.
dump_if_needed()
{
	if [ "$DUMP_INITIAL_STATE" = "y" ]; then
		if [ ! -e "$DUMP_INFO_FILE" ]; then
				if ls "$DUMP_DIR/rdfpatch-"* 1> /dev/null 2>&1; then
						echo "Error: 'rdfpatch-*' files found in '$DUMP_DIR'. Remove 'rdfpatch-*' files before dumping." >&2
						exit 1
				else
					execute_dump
				fi
		else
			assert_dump_completed_normal "$DUMP_INFO_FILE"
		fi
	else
		echo "Not checking dump status because DUMP_INITIAL_STATE is not 'y'" >&2
		if [ ! -e "$STARTED_AT_FILE" ]; then
		    printf $(date +"%Y%m%d%H%M%S") > "$STARTED_AT_FILE"
		    printf 0 > "$COUNT_NQUADS_FILE"
		fi
	fi

	# Quit, in case dump-and-exit was requested.
	if [ "$DUMP_AND_EXIT" = "y" ]; then
		echo "Exiting the Virtuoso quad logger because DUMP_AND_EXIT is 'y'" >&2
		exit 255
	fi
}

###############################
# parse_nquads
# Call vql_parse_trx_files on server.
#
# Globals:      MAX_QUADS_PER_FILE, LOG_FILE_LOCATION
# Arguments:    latestlogsuffix: timestamp of last transaction log inspected
# Returns:      dump stream on &1, can be picked up with -
parse_nquads()
{
    local latestlogsuffix="$1"
	$ISQL_CMD <<-EOF 2>$ISQL_ERROR_FILE
		vql_parse_trx_files('$LOG_FILE_LOCATION', '$latestlogsuffix', $MAX_QUADS_PER_FILE);
		exit;
		EOF
}

###############################
# sync_transaction_logs
# Parse newly found transaction logs to rdf-patch-formatted files in the directory DUMP_DIR with the name pattern
# 'rdf_out_yyyymmddhhmmss-xxxxxxxxxxxxxx', where 'yyyymmddhhmmss' is the local timestamp of the
# start of this function and 'xxxxxxxxxxxxxx' is a 14 digit serial number. In order to make sure new data is
# only updated atomically and will never contain half a patch synchronic processes should not work with
# the last file with this name pattern. This method will create a sham file with the name
# 'rdf_out_99999999999999-99999999999999' when finished,
# thus enabling the processing of the last real 'rdf_out_*' file.
# This method writes the timestamp of the last transaction log processed to the file LAST_LOG_SUFFIX.
# This method reads and keeps track of the amount of N-Quads processed in the file COUNT_NQUADS_FILE.
#
# Globals:      DUMP_DIR, SHAM_RDF_OUT_FILE, LAST_LOG_SUFFIX, COUNT_NQUADS_FILE, STARTED_AT_FILE
# Arguments:    None
# Returns:      None
sync_transaction_logs()
{
    if [ -e "$SHAM_RDF_OUT_FILE" ]; then
		# Prevent posible synchronous processing of the last rdf_out_* file.
		rm "$SHAM_RDF_OUT_FILE"
	fi

    local exp_nquads=$(<"$COUNT_NQUADS_FILE")
    local exp_nfiles=$(<"$COUNT_NFILES_FILE")

	local latestlogsuffix=""
	if [ -e "$LAST_LOG_SUFFIX" ]; then
		latestlogsuffix=$(<"$LAST_LOG_SUFFIX")
	fi
	echo "Reading transaction logs. Last log read had timestamp $latestlogsuffix" >&2

	# write nquads to marked output file
	local mark=$(date +"%Y%m%d%H%M%S")
	local output="$DUMP_DIR/rdf_out_$mark-"

    parse_nquads "$latestlogsuffix" | grep "^#\|^\+\|^-" | csplit -f "$output" -n 14 -sz - "/^# at checkpoint /" {*}
	assert_no_isql_error

    # The last file only contains information on the sync.
	local lastfile=$(ls "$output"* | sort -r | head -n 1)
	if [[ -z "${lastfile// }" ]]; then
        echo "Error: sync_transaction_logs ended abnormal." >&2
        exit 1
	fi
	local nquads=$(cat $lastfile | grep "# quad count" | sed -e s/[^0-9]//g)
	local nfiles=$(cat $lastfile | grep "# file count" | sed -e s/[^0-9]//g)
	local last_log=$(cat $lastfile | grep "# last trx log" | sed -e s/[^0-9]//g)
	rm "$lastfile"

    # Write lastlogsuffix in dedicated file.
	printf "$last_log" > "$LAST_LOG_SUFFIX"

	# Processes in chain will not consider last file (in alphabetical sort order) with pattern rdfpatch-*.
	# Enable processing of last patch file by creating an extra file.
	touch "$SHAM_RDF_OUT_FILE"

	# Keep scores...
    if [ "$nquads" -gt 0 ]; then
	    exp_nquads=$((exp_nquads+nquads))
	    printf "$exp_nquads" > "$COUNT_NQUADS_FILE"
	    exp_nfiles=$((exp_nfiles+nfiles))
	    printf "$exp_nfiles" > "$COUNT_NFILES_FILE"
	fi
	echo "Exported $nquads N-Quads in $nfiles files during this run" >&2
	local start_date=$(<"$STARTED_AT_FILE")
	echo -e "Exported since $start_date: $exp_nquads N-Quads in \t $exp_nfiles streams" >&2

}

###############################
# change_owner_if_needed
#
# Globals:      DUMP_DIR, CHOWN_TO_ID
# Arguments:    None
# Returns:      None
change_owner_if_needed()
{
	if [ -n "${CHOWN_TO_ID:-}" ]; then
		echo "Changin the owner of the files to $CHOWN_TO_ID" >&2
		chown -R "$CHOWN_TO_ID:$CHOWN_TO_ID" "$DUMP_DIR"
	fi
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

change_owner_if_needed

exit 0
