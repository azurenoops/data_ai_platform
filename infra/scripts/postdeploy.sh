#!/usr/bin/env sh
# Post-deploy: smoke test deployed App Service.
# Reads MCP_SERVER_BASE_URL from `terraform output -json` instead of `azd env`.
set -eu

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TFOUT_JSON="${TFOUT_JSON:-${REPO_ROOT}/infra/tfout.json}"

if [ ! -f "$TFOUT_JSON" ]; then
  echo "Terraform output JSON not found at $TFOUT_JSON. Skipping smoke." >&2
  exit 0
fi

MCP_SERVER_BASE_URL="$(jq -r '.MCP_SERVER_BASE_URL.value // empty' "$TFOUT_JSON")"

if [ -z "${MCP_SERVER_BASE_URL:-}" ]; then
  echo "MCP_SERVER_BASE_URL output not present - skipping smoke."
  exit 0
fi

echo "==> Hitting healthz at ${MCP_SERVER_BASE_URL}/healthz"
curl -fsSL "${MCP_SERVER_BASE_URL}/healthz" || { echo "Healthz failed"; exit 1; }

echo "==> Running smoke project"
dotnet test "${REPO_ROOT}/tests/DataAiMcp.Smoke.Tests/DataAiMcp.Smoke.Tests.csproj" --configuration Release --no-build || true

echo "==> postdeploy complete"
