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

split_nquad() {
    filename="$1"
    comments="$2"
    line="$3"

    # Split line on spaces, position of graph iri is second to last in array...
    arr=($(IFS=$'\n'; echo $line | egrep -o '"[^"]*"|\S+'))
    pos=$((${#arr[@]}-2))
    iri_ref="${arr[$pos]}"
    graph="${iri_ref:1:${#iri_ref}-2}"

    # File under base64 of graph
    dir=$(echo $graph | base64)
    mkdir -p "$SINK_DIR/$dir"
    file="$SINK_DIR/$dir/$filename"
    # Use echo to write lines. echo -E = Disable the interpretation of backslash-escaped characters
    if [ ! -e "$file" ]; then
        # if new file stringify comments array with line breaks and write comments first.
        cs=$(IFS=$'\n'; echo "${comments[*]}")
        echo -E "$cs" > "$file"
    fi
    # add line
    echo -E "$line" >> "$file"
}

split_lines_in_file() {
    filename="$1"
    path="$SOURCE_DIR/$filename"
    comments=("# origin $filename")
    line_count=0
    while read line
    do
        if [[ "$line" == \#* ]]; then
            comments+=("$line")
        else
            split_nquad "$filename" "$comments" "$line"
            line_count=$((line_count+1))
        fi
    done < "$path"
    echo "Extracted $line_count N-Quads from $path" >&2
}


split_files_over_graph_iri() {
    prefix="$1"
    arr=()
    for path in "$SOURCE_DIR/$prefix"; do
        filename=$(basename "$path")
        arr+=("$filename")
    done
    if [ ${#arr[@]} -gt 0 ]; then
        unset arr[${#arr[@]}-1]
    fi
    if [ ${#arr[@]} -gt 0 ]; then
        file_count=0
        for filename in "${arr[@]}"; do
            split_lines_in_file "$filename"
            rm "$SOURCE_DIR/$filename"
            file_count=$((file_count+1))
        done
        echo "Done splitting $file_count '$prefix' files over graph iri." >&2
    fi
}

split_files_over_graph_iri "rdfdump-*"
split_files_over_graph_iri "rdfpatch-*"