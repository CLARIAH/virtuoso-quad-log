#!/usr/bin/env bash
set -o nounset
set -o errexit

RUN_INTERVAL=${RUN_INTERVAL:-3600s}

# (Re-)insert stored procedures every time this script runs, so remove flag.
if [ -e md5_stored_procedures ]; then
	rm md5_stored_procedures
fi

echo "Starting quad-logger. RUN_INTERVAL=$RUN_INTERVAL" >&2

while true; do
	bash generate-rdfpatch.sh || echo "Generate failed. Sleep $RUN_INTERVAL" >&2
	sleep ${RUN_INTERVAL}
done
