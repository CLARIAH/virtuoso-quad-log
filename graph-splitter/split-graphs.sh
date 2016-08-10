#!/usr/bin/env bash
set -o nounset
set -o errexit

# Source directory with quad dump/patch files not split over graph iri's.
SOURCE_DIR="${SOURCE_DIR:-/input}"
if [ ! -e "$SOURCE_DIR" ]; then
    mkdir -p "$SOURCE_DIR"
    echo "Created $SOURCE_DIR"
fi

# Sink directory for triple dump/patch files split over graph iri's in iri-morph directory structure.
SINK_DIR="${SINK_DIR:-/output}"
if [ ! -e "$SINK_DIR" ]; then
    mkdir -p "$SINK_DIR"
    echo "Created $SINK_DIR"
fi

split_nquad() {
    path="$1"
    comments="$2"
    line="$3"

    # extract filename
    filename=$(basename "$path")

    # split line on spaces, never mind escaped quotes and right-to-left scriptures,
    # because position of graph iri is second to last in array...
    # and triple is line from character position 0 unto graph start + '.'.
    arr=($(IFS=$'\n'; echo $line | egrep -o '"[^"]*"|\S+'))
    grp=$((${#arr[@]}-2))
    graph="${arr[$grp]}"
    # construct the triple...
    # grl=$((${#graph}+2))
    # len=$((${#line}-$grl))
    # len=$((${#line}-2))
    # new_line="${line:0:len}."
    # or keep the nquad...
    new_line="$line"

    # split graph iri into directory paths
    # words=($(echo $graph | egrep -o '\b[^<:\./?&=>]+\b'))
    # dirs=$(IFS=/; echo "${words[*]}")
    # or base64-encode graph iri
    dirs=$(echo $graph | base64)

    mkdir -p "$SINK_DIR/$dirs"
    file="$SINK_DIR/$dirs/$filename"
    # Use echo to write lines. echo -E = Disable the interpretation of backslash-escaped characters
    if [ ! -e "$file" ]; then
        # if new file stringify comments array with line breaks and write comments first.
        cs=$(IFS=$'\n'; echo "${comments[*]}")
        echo -E "$cs" > "$file"
    fi
    # add line
    echo -E "$new_line" >> "$file"
}

split_lines_in_file() {
    path="$1"
    comments=("# origin $path")
    line_count=0
    while read line
    do
        if [[ "$line" == \#* ]]; then
            comments+=("$line")
        else
            split_nquad "$path" "$comments" "$line"
            line_count=$((line_count+1))
        fi
    done < "$path"
    echo "Extracted $line_count N-Quads from $path"
}

split_files_over_graph_iri() {
    for path in $SOURCE_DIR/*; do
        filename=$(basename "$path")
        case "$filename" in
            rdfdump-* | rdfpatch-* )
                split_lines_in_file "$path"
                ;;
        esac
    done
}



split_files_over_graph_iri