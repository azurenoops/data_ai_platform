#!/usr/bin/env bash
set -euo pipefail

# Runs the SQL demo ingestion pipeline and prints a compact summary.
# Usage:
#   ./demo-data/run-sql-demo-pipeline.sh
#   ./demo-data/run-sql-demo-pipeline.sh <existing-run-id>

RG="rg-dataai-centralus"
ADF="adf-04753339edf2b"
PIPELINE="pl_sql_mi_to_adls"

if [[ "${1-}" != "" ]]; then
  RUN_ID="$1"
  echo "Using existing run: $RUN_ID"
else
  RUN_ID=$(az datafactory pipeline create-run \
    --resource-group "$RG" \
    --factory-name "$ADF" \
    --name "$PIPELINE" \
    --query runId -o tsv)
  echo "Started run: $RUN_ID"
fi

for i in {1..36}; do
  run_state=$(az datafactory pipeline-run show \
    --resource-group "$RG" \
    --factory-name "$ADF" \
    --run-id "$RUN_ID" \
    --query status -o tsv)
  echo "poll-$i state=$run_state"

  if [[ "$run_state" == "Succeeded" || "$run_state" == "Failed" || "$run_state" == "Cancelled" ]]; then
    break
  fi

  sleep 10
done

echo "\nPipeline run summary"
az datafactory pipeline-run show \
  --resource-group "$RG" \
  --factory-name "$ADF" \
  --run-id "$RUN_ID" \
  --query "{runId:runId,status:status,runStart:runStart,runEnd:runEnd,message:message}" -o json

echo "\nCopy activity summary"
AFTER_UTC=$(date -u -v-2H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)
BEFORE_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
az datafactory activity-run query-by-pipeline-run \
  --resource-group "$RG" \
  --factory-name "$ADF" \
  --run-id "$RUN_ID" \
  --last-updated-after "$AFTER_UTC" \
  --last-updated-before "$BEFORE_UTC" \
  --query "value[?activityName=='CopyTable'].{status:status,rowsCopied:output.rowsCopied,filesWritten:output.filesWritten,dataRead:output.dataRead,errorCode:error.errorCode}" -o table

echo "\nTip: if you need the raw JSON, rerun with:"
echo "az datafactory activity-run query-by-pipeline-run --resource-group $RG --factory-name $ADF --run-id $RUN_ID --last-updated-after \"$AFTER_UTC\" --last-updated-before \"$BEFORE_UTC\" -o json"
