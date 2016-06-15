#!/usr/bin/env bash
set -o nounset
set -o errexit

RUN_INTERVAL=${RUN_INTERVAL:-3600s}

if [ "${1:-}" = "server" ]; then
	/usr/local/bin/virtuoso-t -f -c /usr/local/var/lib/virtuoso/db/virtuoso.ini
else
	while true; do
		echo "Running generate..."
		bash generate-rdfpatch.sh
		echo "done. sleep $RUN_INTERVAL"
		sleep ${RUN_INTERVAL}
	done
fi
