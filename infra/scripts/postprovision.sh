#!/usr/bin/env sh
# Post-provision: provision/update the AI Search index, push Synapse view DDL.
# Reads source-of-truth values from `terraform output -json` instead of `azd env`.
#
# Usage (locally):
#   cd infra
#   terraform output -json > /tmp/tfout.json
#   TFOUT_JSON=/tmp/tfout.json ../infra/scripts/postprovision.sh
#
# Usage (CI): the terraform.yml workflow uploads outputs.json as an artifact and
# downstream jobs export TFOUT_JSON before invoking this script.
set -eu

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TFOUT_JSON="${TFOUT_JSON:-${REPO_ROOT}/infra/tfout.json}"

if [ ! -f "$TFOUT_JSON" ]; then
  echo "Terraform output JSON not found at $TFOUT_JSON. Run 'terraform output -json > tfout.json' or set TFOUT_JSON." >&2
  exit 1
fi

echo "==> Loading terraform outputs from $TFOUT_JSON"
export AZURE_TENANT_ID="$(jq -r '.AZURE_TENANT_ID.value' "$TFOUT_JSON")"
export AZURE_LOCATION="$(jq -r '.AZURE_LOCATION.value' "$TFOUT_JSON")"
export AZURE_RESOURCE_GROUP="$(jq -r '.AZURE_RESOURCE_GROUP.value' "$TFOUT_JSON")"
export STORAGE_ACCOUNT_NAME="$(jq -r '.STORAGE_ACCOUNT_NAME.value' "$TFOUT_JSON")"
export STORAGE_BLOB_ENDPOINT="$(jq -r '.STORAGE_BLOB_ENDPOINT.value' "$TFOUT_JSON")"
export SEARCH_ENDPOINT="$(jq -r '.SEARCH_ENDPOINT.value' "$TFOUT_JSON")"
export SEARCH_INDEX_NAME="$(jq -r '.SEARCH_INDEX_NAME.value' "$TFOUT_JSON")"
export SEARCH_NAME="$(jq -r '.SEARCH_NAME.value' "$TFOUT_JSON")"
export FOUNDRY_ACCOUNT_ENDPOINT="$(jq -r '.FOUNDRY_ACCOUNT_ENDPOINT.value' "$TFOUT_JSON")"
export FOUNDRY_EMBEDDING_DEPLOYMENT="$(jq -r '.FOUNDRY_EMBEDDING_DEPLOYMENT.value' "$TFOUT_JSON")"
export SYNAPSE_SERVERLESS_SQL_ENDPOINT="$(jq -r '.SYNAPSE_SERVERLESS_SQL_ENDPOINT.value' "$TFOUT_JSON")"
export ENABLE_CMK="$(jq -r '.ENABLE_CMK.value' "$TFOUT_JSON")"
export CMK_KEY_URI="$(jq -r '.CMK_KEY_URI.value' "$TFOUT_JSON")"

# The shared .NET services bind options from section-shaped environment names
# (Search__Endpoint, Search__IndexName, ...), not the legacy flat SEARCH_*
# variables above. Export both so postprovision works locally and in CI.
export Search__Endpoint="$SEARCH_ENDPOINT"
export Search__IndexName="$SEARCH_INDEX_NAME"

if [ "${ENABLE_CMK:-false}" = "true" ] && [ -n "${CMK_KEY_URI:-}" ] && [ "$CMK_KEY_URI" != "null" ]; then
  Search__CmkKeyVaultUri="$(printf '%s' "$CMK_KEY_URI" | sed -E 's#(https://[^/]+/).*#\1#')"
  Search__CmkKeyName="$(printf '%s' "$CMK_KEY_URI" | sed -E 's#^.*/keys/([^/]+).*$#\1#')"
  Search__CmkKeyVersion="$(printf '%s' "$CMK_KEY_URI" | sed -nE 's#^.*/keys/[^/]+/([^/]+)$#\1#p')"
  export Search__CmkKeyVaultUri Search__CmkKeyName Search__CmkKeyVersion
fi

echo "==> Provisioning AI Search index"
dotnet run --project "${REPO_ROOT}/src/DataAiMcp.Tools.IndexProvisioner/DataAiMcp.Tools.IndexProvisioner.csproj" --configuration Release

if [ -n "${SYNAPSE_SERVERLESS_SQL_ENDPOINT:-}" ] && [ -n "${STORAGE_ACCOUNT_NAME:-}" ]; then
  echo "==> Pushing Synapse views (placeholder - requires sqlcmd / az synapse with AAD)"
  for sql in "${REPO_ROOT}"/infra/synapse/views/*.sql; do
    echo "  - $sql"
    sed "s/__STORAGE_ACCOUNT__/${STORAGE_ACCOUNT_NAME}/g" "$sql" > "${sql}.tmp"
    # Recommended: install sqlcmd locally and uncomment:
    # sqlcmd -S "${SYNAPSE_SERVERLESS_SQL_ENDPOINT}" -G -d master -i "${sql}.tmp"
    rm -f "${sql}.tmp"
  done
fi

echo "==> postprovision complete"
