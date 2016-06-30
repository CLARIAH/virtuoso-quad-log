#!/usr/bin/env bash

RUN_INTERVAL=${RUN_INTERVAL:-10s}

inputdir="${DATA_DIR:-/input}"
outputdir="${DATA_DIR:-/output}"

while true; do
  sleep ${RUN_INTERVAL}
  if [ -d "$inputdir/newdata" ]; then
    echo "Adding metadata..."
    mv "$inputdir/newdata" "$inputdir/addingmetadata"
    if [ $? = 0 ]; then
      ./resource-list.py --resource-url "${HTTP_SERVER_URL}" --resource-dir "$inputdir/addingmetadata"
      if [ -n "${CHOWN_TO_ID:-}" ]; then
        chown -R "$CHOWN_TO_ID:$CHOWN_TO_ID" "$inputdir/addingmetadata"
      fi

      find "$inputdir/"
      mv -n "$inputdir/addingmetadata/rdf"* "$outputdir" # move the rdf files over -n skips files that already exist
      mv "$inputdir/addingmetadata/resource-list.xml" "$outputdir"

      mv -n "$inputdir/addingmetadata/capability-list.xml" "$outputdir"
      mkdir -p "$outputdir/.well-known"
      mv -n "$inputdir/addingmetadata/.well-known/resourcesync" "$outputdir/.well-known"

      echo "done. sleep $RUN_INTERVAL"
    else
      echo "newdata was there a second ago and now its gone. Might be a race condition."
    fi
  else
    echo "No new data available..."
  fi
done



