terraform {
  # Backend values are supplied at `terraform init` time via -backend-config flags.
  # The placeholders below satisfy the new parse-time validation in azurerm backend
  # but should always be overridden via:
  #   terraform init \
  #     -backend-config="resource_group_name=<state-rg>" \
  #     -backend-config="storage_account_name=<state-sa>" \
  #     -backend-config="container_name=tfstate" \
  #     -backend-config="key=data-ai-mcp.tfstate" \
  #     -backend-config="use_oidc=true"
  backend "azurerm" {
    resource_group_name  = "PLACEHOLDER"
    storage_account_name = "PLACEHOLDER"
    container_name       = "tfstate"
    key                  = "data-ai-mcp.tfstate"
  }
}
