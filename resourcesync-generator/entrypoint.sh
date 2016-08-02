#!/usr/bin/env bash

RUN_INTERVAL=${RUN_INTERVAL:-3600s}
MAX_FILES_IN_ZIP=${MAX_FILES_IN_ZIP:-100}
WRITE_SEPARATE_MANIFEST=${WRITE_SEPARATE_MANIFEST:-y}
MOVE_RESOURCES=${MOVE_RESOURCES:-n}

RESOURCE_DIR="${DATA_DIR:-/input}"
PUBLISH_DIR="${DATA_DIR:-/output}"

while true; do
  echo "sleep $RUN_INTERVAL."
  sleep ${RUN_INTERVAL}
  ./rsync.py --resource_dir "$RESOURCE_DIR" \
  --publish_dir "$PUBLISH_DIR" \
  --publish_url "${HTTP_SERVER_URL}" \
  --max_files_in_zip "${MAX_FILES_IN_ZIP}" \
  --write_separate_manifest "${WRITE_SEPARATE_MANIFEST}" \
  --move_resources "${MOVE_RESOURCES}"

  if [ -n "${CHOWN_TO_ID:-}" ]; then
        chown -R "$CHOWN_TO_ID:$CHOWN_TO_ID" "$PUBLISH_DIR"
  fi
done
