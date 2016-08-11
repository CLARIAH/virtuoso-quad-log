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

# File constituting handshake between this service and chained services.
HS_SOURCE_FILE="$SOURCE_DIR/started_at.txt"
HS_SINK_FILE="$SINK_DIR/started_at.txt"

###############################
# process_nquad
# File given N-Quad per graph iri in sink directory.
# N-Quads will be stored in files with names equal to their source file, under a directory that is the
# base64 translation of their graph iri in the sink directory.
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

    # Split line on spaces, position of graph iri is second to last in array...
    local arr=($(IFS=$'\n'; echo $line | egrep -o '"[^"]*"|\S+'))
    local pos=$((${#arr[@]}-2))
    local iri_ref="${arr[$pos]}"
    local graph="${iri_ref:1:${#iri_ref}-2}"

    # File under base64 of graph
    local dir=$(echo $graph | base64)
    mkdir -p "$SINK_DIR/$dir"
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

    while read line
    do
        if [[ "$line" == \#* ]]; then
            comments+=("$line")
        else
            process_nquad "$filename" comments[@] "$line"
            line_count=$((line_count+1))
        fi
    done < "$path"
    echo "Extracted $line_count N-Quads from $path" >&2
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
    [ -f "$HS_SOURCE_FILE" ] && { hs_source=$(<"$HS_SOURCE_FILE"); } || { hs_source=0; }
    [ -f "$HS_SINK_FILE" ] && { hs_sink=$(<"$HS_SINK_FILE"); } || { hs_sink=0; }

    if [ "$hs_source" == 0 ]; then
        echo "Error: No source handshake found. Not interfering with status quo." >&2
        exit 1
    fi

    if [ "$hs_sink" == 0 ]; then
        # legal state only at start and sink dir is empty
        if [ "$(ls -A $SINK_DIR)" ]; then
            echo "Error: No sink handshake found and $SINK_DIR not empty." >&2
            echo "Not interfering with status quo." >&2
            exit 2
        fi
    fi

    if [ "$hs_source" != "$hs_sink" ]; then
        echo "Handshake not equal. source=$hs_source sink=$hs_sink" >&2
        echo "Cleaning $SINK_DIR" >&2
        rm -Rf "$SINK_DIR/*"
        hs_sink=0
    fi

    if [ "$hs_sink" == 0 ]; then
        printf "$hs_source" > "$HS_SINK_FILE"
        echo "Signed new handshake: $hs_source" >&2
    fi

    echo "Synchronizing state on handshake $hs_source." >&2
}

# Verify that handshake files in source directory and sink directory are equal.
verify_handshake

# Split rdf-patch files in the source directory into rdf-patch files in the sink directory per graph.
split_files_over_graph_iri "rdfpatch-*"