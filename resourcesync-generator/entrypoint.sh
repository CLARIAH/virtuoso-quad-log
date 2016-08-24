#!/usr/bin/env bash

RUN_INTERVAL=${RUN_INTERVAL:-3600s}
MAX_FILES_COMPRESSED=${MAX_FILES_COMPRESSED:-1000}
WRITE_SEPARATE_MANIFEST=${WRITE_SEPARATE_MANIFEST:-y}
MOVE_RESOURCES=${MOVE_RESOURCES:-n}
SOURCE_DIR="${SOURCE_DIR:-/input}"
SINK_DIR="${SINK_DIR:-/output}"
BUILDER_CLASS="${BUILDER_CLASS:-zipsynchronizer.ZipSynchronizer}"

echo "Starting resourcesync-generator. RUN_INTERVAL=$RUN_INTERVAL" >&2

while true; do

  ./rsync.py --source_dir "$SOURCE_DIR" \
  --sink_dir "$SINK_DIR" \
  --publish_url "${HTTP_SERVER_URL}" \
  --builder_class "${BUILDER_CLASS}" \
  --max_files_compressed "${MAX_FILES_COMPRESSED}" \
  --write_separate_manifest "${WRITE_SEPARATE_MANIFEST}" \
  --move_resources "${MOVE_RESOURCES}"

  if [ -n "${CHOWN_TO_ID:-}" ]; then
        chown -R "$CHOWN_TO_ID:$CHOWN_TO_ID" "$PUBLISH_DIR"
  fi

  sleep ${RUN_INTERVAL}
done
