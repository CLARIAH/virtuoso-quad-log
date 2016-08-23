#!/usr/bin/env bash
set -o nounset
set -o errexit

RUN_INTERVAL=${RUN_INTERVAL:-3600s}

echo "Starting graph-splitter. RUN_INTERVAL=$RUN_INTERVAL" >&2

while true; do
	bash split-graphs.sh || echo "Split failed. Sleep $RUN_INTERVAL" >&2
	sleep ${RUN_INTERVAL}
done
