#!/usr/bin/env bash
set -o nounset
set -o errexit

# Source directory with rdf-patch files not split over graph iri's.
SOURCE_DIR="${SOURCE_DIR:-/input}"
if [ ! -e "$SOURCE_DIR" ]; then
    mkdir -p "$SOURCE_DIR"
    echo "Created $SOURCE_DIR"
fi

# Sink directory for rdf-patch files split over graph iri's in base64-encoded directories.
SINK_DIR="${SINK_DIR:-/output}"
if [ ! -e "$SINK_DIR" ]; then
    mkdir -p "$SINK_DIR"
    echo "Created $SINK_DIR"
fi

# Files constituting handshake between this service and chained services.
HS_SOURCE_FILE="$SOURCE_DIR/vql_started_at.txt"
HS_SINK_FILE="$SINK_DIR/vql_started_at.txt"

# File mapping between graph iri and base64-translated directory name.
INDEX_FILE="$SINK_DIR/vql_graph_folder.csv"

# File enabling processing of last real 'rdf_out_*' file by chained processes
SHAM_PATCH_FILE="rdf_out_99999999999999-99999999999999"

###############################
# Keep track of exported (by quad-logger) and filed (by graph-splitter) quads.
# File with total number of exported N-Quads thus far
EXPORTED_NQUADS_FILE="$SOURCE_DIR/vql_nquads_count.txt"

# File with total number filed N-Quads thus far.
FILED_NQUADS_FILE="$SINK_DIR/vql_nquads_count.txt"

# Exported N-Quads thus far - Read only.
[ -f "$EXPORTED_NQUADS_FILE" ] && { EXPORTED_NQUADS=$(<"$EXPORTED_NQUADS_FILE"); } || { EXPORTED_NQUADS=0; }

# Filed N-Quads by this routine thus far
[ -f "$FILED_NQUADS_FILE" ] && { FILED_NQUADS=$(<"$FILED_NQUADS_FILE"); } || { FILED_NQUADS=0; }

###############################
# Keep track of exported (by quad-logger) and filed (by graph-splitter) files.
# File with total number of exported files thus far
EXPORTED_FILES_FILE="$SOURCE_DIR/vql_files_count.txt"

# File with total number filed files thus far.
FILED_FILES_FILE="$SINK_DIR/vql_files_count.txt"

# Exported files thus far - Read only.
[ -f "$EXPORTED_FILES_FILE" ] && { EXPORTED_FILES=$(<"$EXPORTED_FILES_FILE"); } || { EXPORTED_FILES=0; }

# Filed files by this routine thus far
[ -f "$FILED_FILES_FILE" ] && { FILED_FILES=$(<"$FILED_FILES_FILE"); } || { FILED_FILES=0; }


# Count N-Quads this run
COUNT_NQUADS=0

# Count of files this run
COUNT_FILES=0


process_file() {

    filename="$1"
    src_file="$SOURCE_DIR/$filename"

    header=$(head -n 3 "$src_file")
    graph=$(echo "$header" | sed -n 's/.*# graph         \(.*\) /\1/p')
    base=$(echo "$header" | sed -n 's/.*# base64        \(.*\) /\1/p')

    if [ "$graph" == "" ] && [ "$base" == "" ]; then
        # this is a message file, ending a dump ar patch run from quad-logger.
        # should have been removed but just in case...
        return 0
    fi

    if [ ! -d "$SINK_DIR/$base" ]; then
        mkdir -p "$SINK_DIR/$base"
        printf "$graph,$base\n" >> "$INDEX_FILE"
    fi

    snk_file="$SINK_DIR/$base/$filename"
    mv "$src_file" "$snk_file"

    # Statistics..
    COUNT_FILES=$((COUNT_FILES + 1))

    # each file has 3 header lines
    local nquads=$(($(wc -l "$snk_file" | grep -o '[0-9]\+' | head -1) - 3))
    COUNT_NQUADS=$((COUNT_NQUADS + nquads))
}

###############################
# distribute_files_per_graph_iri
# Distribute rdf-patch files in the source directory over directories per graph in the sink directory..
#
# Globals:      SOURCE_DIR, SINK_DIR
# Arguments:    None
# Returns:      None
distribute_files_per_graph_iri() {

    local prefix="rdf_out_*"
    local arr=()

    for path in $SOURCE_DIR/$prefix; do
        arr+=($(basename "$path"))
    done
    if [ ${#arr[@]} -gt 0 ]; then
        # do not process the last file (alphabetically) - chained source services may be handling those.
        unset arr[${#arr[@]}-1]
    fi
    echo "Found ${#arr[@]} files with prefix $prefix in $SOURCE_DIR" >&2
    if [ ${#arr[@]} -gt 0 ]; then
        for filename in "${arr[@]}"; do
            process_file "$filename"
        done
        echo "Done distributing by graph: $COUNT_NQUADS N-Quads in $COUNT_FILES files" >&2
    fi
}



###############################
# verify_handshake
# Verify that handshake files in source directory and sink directory are equal, otherwise take appropriate action.
#
# Globals:      SOURCE_DIR, SINK_DIR
# Arguments:    None
# Returns:      None
# Exit status:  1 if handshake file in SOURCE_DIR not found, 2 if handshake file in SINK_DIR not found.
verify_handshake() {
    [ -f "$HS_SOURCE_FILE" ] && { HS_SOURCE=$(<"$HS_SOURCE_FILE"); } || { HS_SOURCE=0; }
    [ -f "$HS_SINK_FILE" ] && { hs_sink=$(<"$HS_SINK_FILE"); } || { hs_sink=0; }

    if [ "$HS_SOURCE" == 0 ]; then
        echo "Error: No source handshake found. Not interfering with status quo." >&2
        exit 1
    fi

    if [ "$hs_sink" == 0 ] && [ "$(ls -A $SINK_DIR)" ]; then
        echo "Error: No sink handshake found and $SINK_DIR not empty." >&2
        echo "Not interfering with status quo." >&2
        exit 2
    fi

    if [ "$HS_SOURCE" != "$hs_sink" ]; then
        echo "Handshake not equal. source=$HS_SOURCE sink=$hs_sink" >&2
        echo "Cleaning $SINK_DIR" >&2
        rm -Rf "$SINK_DIR/*"
        hs_sink=0
    fi

    if [ "$hs_sink" == 0 ]; then
        printf "$HS_SOURCE" > "$HS_SINK_FILE"
        echo "Signed new handshake: $HS_SOURCE" >&2
    fi

    # echo "Synchronizing state on handshake $HS_SOURCE." >&2
}

###############################
# disable_processing_of_last_patch
# Disable processing of last real 'rdfpatch-*' file in sink directory by chained processes.
#
# Globals:      SINK_DIR, SHAM_PATCH_FILE
# Arguments:    None
# Returns:      None
disable_processing_of_last_patch() {
    for dir in $SINK_DIR/*/; do
        if [ -e "$dir$SHAM_PATCH_FILE" ]; then
            rm "$dir$SHAM_PATCH_FILE"
        fi
    done
}

###############################
# enable_processing_of_last_patch
# Enable processing of last real 'rdfpatch-*' file in sink directory by chained processes.
#
# Globals:      SINK_DIR, SHAM_PATCH_FILE
# Arguments:    None
# Returns:      None
enable_processing_of_last_patch() {
    for dir in $SINK_DIR/*/; do
        if [ -d "$dir" ]; then
            touch "$dir$SHAM_PATCH_FILE"
        fi
    done
}

###############################
# change_owner_if_needed
#
# Globals:      SINK_DIR, CHOWN_TO_ID
# Arguments:    None
# Returns:      None
change_owner_if_needed()
{
	if [ -n "${CHOWN_TO_ID:-}" ]; then
		echo "Changin the owner of the files to $CHOWN_TO_ID" >&2
		chown -R "$CHOWN_TO_ID:$CHOWN_TO_ID" "$SINK_DIR"
	fi
}

report_totals()
{
    if [ "$COUNT_NQUADS" > 0 ] || [ "$COUNT_FILES" > 0 ]; then
        FILED_FILES=$((FILED_FILES + COUNT_FILES))
        FILED_NQUADS=$((FILED_NQUADS + COUNT_NQUADS))
        printf "$FILED_FILES" > "$FILED_FILES_FILE"
        printf "$FILED_NQUADS" > "$FILED_NQUADS_FILE"
    fi

    if [ "$EXPORTED_NQUADS" != "$FILED_NQUADS" ]; then
        echo "INFO: Quad count out of sync: exported N-Quads=$EXPORTED_NQUADS, filed N-Quads=$FILED_NQUADS" >&2
    fi

    if [ "$EXPORTED_FILES" != "$FILED_FILES" ]; then
        echo "INFO: File count out of sync: exported files=$EXPORTED_FILES, filed files=$FILED_FILES" >&2
    fi
    #     ====== Exported since 20160822122410: 1158 N-Quads in 15 files
    echo "========= Filed since $HS_SOURCE: $FILED_NQUADS N-Quads in $FILED_FILES files"
}

# Verify that handshake files in source directory and sink directory are equal.
verify_handshake

# Disable processing of last real 'rdfpatch-*' file in sink directory by chained processes.
disable_processing_of_last_patch

# distribute rdf-patch files in the source directory over directories per graph in the sink directory.
distribute_files_per_graph_iri

# Enable processing of last real 'rdfpatch-*' file in sink directory by chained processes.
enable_processing_of_last_patch

change_owner_if_needed

report_totals




