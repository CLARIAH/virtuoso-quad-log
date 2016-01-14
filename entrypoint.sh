#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail

if [ "${1:-}" = "server" ]; then
	/usr/local/bin/virtuoso-t -f -c /usr/local/var/lib/virtuoso/db/virtuoso.ini
else
	while true; do
		echo "Running generate..."
		bash generate-rdfpatch.sh
		sleep ${RUN_INTERVAL:-3600}
	done
fi
