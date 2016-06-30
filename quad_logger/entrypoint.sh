#!/usr/bin/env bash
set -o nounset
set -o errexit

RUN_INTERVAL=${RUN_INTERVAL:-3600s}

while true; do
	echo "Running generate..."
	bash generate-rdfpatch.sh && echo "generate successfull. sleep $RUN_INTERVAL" || echo "generate failed. sleep $RUN_INTERVAL"
	sleep ${RUN_INTERVAL}
done
