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
HS_SOURCE_FILE="$SOURCE_DIR/started_at.txt"
HS_SINK_FILE="$SINK_DIR/started_at.txt"

# File mapping between graph iri and base64-translated directory name. Also indicates that sources have been split.
INDEX_FILE="$SINK_DIR/index.csv"

# File enabling processing of last real 'rdfpatch-*' file by chained processes
SHAM_PATCH_FILE="rdfpatch-99999999999999"

# File with total number of exported N-Quads thus far
EXPORTED_NQUADS_FILE="$SOURCE_DIR/nquads_count.txt"

# File with total number filed N-Quads thus far.
FILED_NQUADS_FILE="$SINK_DIR/nquads_count.txt"

# Exported N-Quads thus far - Read only.
[ -f "$EXPORTED_NQUADS_FILE" ] && { EXPORTED_NQUADS=$(<"$EXPORTED_NQUADS_FILE"); } || { EXPORTED_NQUADS=0; }

# Filed N-Quads by this routine thus far
[ -f "$FILED_NQUADS_FILE" ] && { FILED_NQUADS=$(<"$FILED_NQUADS_FILE"); } || { FILED_NQUADS=0; }

# Count N-Quads this run
COUNT_NQUADS=0


###############################
# process_nquad
# File given N-Quad per graph iri in sink directory.
# N-Quads will be stored in files with names equal to their source file, under a directory
# with a name that is the base64 translation of their graph iri. All will go into the sink directory.
#
# Globals:      SINK_DIR
# Arguments:    filename: the name of the file in SOURCE_DIR
#               comments: an array of comment lines found at the beginning of the file in SOURCE_DIR
#               line: the N-Quad to file
# Returns:      None
process_nquad() {
    local filename="$1"
    declare -a header=("${!2}")
    local line="$3"

    # Split line on spaces, position of graph iri is second to last in resulting array...
    local arr=($(IFS=$'\n'; echo $line | egrep -o '"[^"]*"|\S+'))
    local pos=$((${#arr[@]}-2))
    local iri_ref="${arr[$pos]}"
    local graph="${iri_ref:1:${#iri_ref}-2}"

    # File under base64 of graph
    local dir=$(echo $graph | base64)
    if [ ! -d "$SINK_DIR/$dir" ]; then
        mkdir -p "$SINK_DIR/$dir"
        echo -E "$graph,$dir" >> "$INDEX_FILE"
    fi
    local file="$SINK_DIR/$dir/$filename"
    # Use echo to write lines. echo -E = Disable the interpretation of backslash-escaped characters
    if [ ! -e "$file" ]; then
        # if new file stringify header array with line breaks and write header first.
        local cs=$(IFS=$'\n'; echo "${header[*]}")
        echo -E "$cs" > "$file"
    fi
    # add line
    echo -E "$line" >> "$file"
}

###############################
# process_lines_in_file
# Process the lines in a file one by one.
# Lines containing N-Quads will be shifted to files in the sink directory in accordance with the graph they
# belong to. We assume that comment lines are all at the beginning of a file.
#
# Globals:      SOURCE_DIR
# Arguments:    filename: the name of the file in SOURCE_DIR
# Returns:      None
process_lines_in_file() {
    local filename="$1"
    local path="$SOURCE_DIR/$filename"
    local comments=("# origin $filename")
    local line_count=0

    while read -r line || [ -n "$line" ];  # or: in case last line in file does not end with new line character.
    do
        if [[ "$line" == \#* ]]; then
            comments+=("$line")
        else
            process_nquad "$filename" comments[@] "$line"
            line_count=$((line_count+1))
        fi
    done < "$path"
    echo "Extracted $line_count N-Quads from $path" >&2
    COUNT_NQUADS=$(($COUNT_NQUADS+$line_count))
}

###############################
# split_files_over_graph_iri
# Split rdf-patch files in the source directory into rdf-patch files in the sink directory per graph.
# The produced files in the sink directory will be in subdirectories with names that are the base64
# translation of the graph iri. Processed files in the source directory will be removed.
#
# Globals:      SOURCE_DIR
# Arguments:    prefix: common prefix of the files in SOURCE_DIR
# Returns:      None
split_files_over_graph_iri() {
    local prefix="$1"
    local arr=()

    for path in $SOURCE_DIR/$prefix; do
        local filename=$(basename "$path")
        arr+=("$filename")
    done
    if [ ${#arr[@]} -gt 0 ]; then
        # do not process the last file (alphabetically) - chained source services may be handling those.
        unset arr[${#arr[@]}-1]
    fi
    echo "Found ${#arr[@]} files with prefix $prefix in $SOURCE_DIR" >&2
    if [ ${#arr[@]} -gt 0 ]; then
        local file_count=0
        for filename in "${arr[@]}"; do
            process_lines_in_file "$filename"
            rm "$SOURCE_DIR/$filename"
            file_count=$((file_count+1))
        done
        echo "Done splitting $file_count '$prefix' files over graph iri." >&2
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

# Verify that handshake files in source directory and sink directory are equal.
verify_handshake

# Disable processing of last real 'rdfpatch-*' file in sink directory by chained processes.
disable_processing_of_last_patch

# Split rdf-patch files in the source directory into rdf-patch files in the sink directory per graph.
split_files_over_graph_iri "rdfpatch-*"

# Enable processing of last real 'rdfpatch-*' file in sink directory by chained processes.
enable_processing_of_last_patch

if [ "$COUNT_NQUADS" -gt 0 ]; then
    FILED_NQUADS=$((FILED_NQUADS+COUNT_NQUADS))
    printf "$FILED_NQUADS" > "$FILED_NQUADS_FILE"
fi

echo "Filed $COUNT_NQUADS N-Quads during this run" >&2
echo "========= Total of filed N-Quads since $HS_SOURCE: $FILED_NQUADS" >&2

if [ "$EXPORTED_NQUADS" != "$FILED_NQUADS" ]; then
    diff=$((EXPORTED_NQUADS-FILED_NQUADS))
    echo -e "WARNING: Total of exported N-Quads not equal to total of filed N-Quads. \
    \n\texported: $EXPORTED_NQUADS, filed: $FILED_NQUADS, difference: $diff"
fi

change_owner_if_needed


