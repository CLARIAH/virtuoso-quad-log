#!/usr/bin/env bash
set -o nounset
set -o errexit

RUN_INTERVAL=${RUN_INTERVAL:-3600s}

while true; do
	echo "Splitting graphs..."
	bash split-graphs.sh && echo "split successfull. sleep $RUN_INTERVAL" >&2 || echo "split failed. sleep $RUN_INTERVAL" >&2
	sleep ${RUN_INTERVAL}
done