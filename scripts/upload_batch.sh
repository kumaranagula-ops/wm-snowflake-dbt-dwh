#!/usr/bin/env bash
# Upload one batch of source files to the Snowflake internal stage, keeping the folder layout.
#   ./scripts/upload_batch.sh batch_1            (then run core/05 or EXECUTE TASK UTIL.TSK_EOD_ROOT)
#   ./scripts/upload_batch.sh batch_2
# Needs the Snowflake CLI (`pip install snowflake-cli`) with a connection in ~/.snowflake/connections.toml.
# Optional: SNOW_CONNECTION=<name> to pick a non-default connection.
set -euo pipefail
BATCH="${1:?usage: upload_batch.sh batch_1|batch_2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/data/$BATCH"
CONN_ARGS=()
[[ -n "${SNOW_CONNECTION:-}" ]] && CONN_ARGS=(--connection "$SNOW_CONNECTION")

[[ -d "$SRC" ]] || { echo "No such folder: $SRC"; exit 1; }

find "$SRC" -type f | sed "s#^$SRC/##" | xargs -n1 dirname | sort -u | while read -r rel; do
  echo ">> PUT $rel"
  snow sql ${CONN_ARGS[@]+"${CONN_ARGS[@]}"} -q \
    "PUT 'file://$SRC/$rel/*' @WM_MICRO.UTIL.STG_LANDING/$rel/ AUTO_COMPRESS = TRUE OVERWRITE = FALSE"
done

snow sql ${CONN_ARGS[@]+"${CONN_ARGS[@]}"} -q "ALTER STAGE WM_MICRO.UTIL.STG_LANDING REFRESH"
snow sql ${CONN_ARGS[@]+"${CONN_ARGS[@]}"} -q "LIST @WM_MICRO.UTIL.STG_LANDING"
