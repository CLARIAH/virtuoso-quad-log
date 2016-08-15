#!/usr/bin/env bash

RUN_INTERVAL=${RUN_INTERVAL:-3600s}
MAX_FILES_COMPRESSED=${MAX_FILES_COMPRESSED:-100}
WRITE_SEPARATE_MANIFEST=${WRITE_SEPARATE_MANIFEST:-y}
MOVE_RESOURCES=${MOVE_RESOURCES:-n}

RESOURCE_DIR="${DATA_DIR:-/input}"
PUBLISH_DIR="${DATA_DIR:-/output}"
SYNCHRONIZER_CLASS="${SYNCHRONIZER_CLASS:-zipsynchronizer.ZipSynchronizer}"

while true; do
  echo "sleep $RUN_INTERVAL."
  sleep ${RUN_INTERVAL}
  ./rsync.py --resource_dir "$RESOURCE_DIR" \
  --publish_dir "$PUBLISH_DIR" \
  --publish_url "${HTTP_SERVER_URL}" \
  --synchronizer_class "${SYNCHRONIZER_CLASS}" \
  --max_files_compressed "${MAX_FILES_COMPRESSED}" \
  --write_separate_manifest "${WRITE_SEPARATE_MANIFEST}" \
  --move_resources "${MOVE_RESOURCES}"

  if [ -n "${CHOWN_TO_ID:-}" ]; then
        chown -R "$CHOWN_TO_ID:$CHOWN_TO_ID" "$PUBLISH_DIR"
  fi
done
