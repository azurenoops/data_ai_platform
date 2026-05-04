# Terraform state bootstrap

This sub-config provisions the Azure resources that hold Terraform remote state for the rest of `infra/`. It is **run once per state environment** (typically once total) with **local state** — its own outputs feed the `terraform init -backend-config=...` flags used by the parent config.

## Run once

```bash
cd infra/bootstrap
az login
az account set --subscription <subscription-id>

terraform init
terraform apply \
  -var environment_name=shared \
  -var location=eastus2 \
  -var ci_principal_id=<github-actions-sp-object-id>
```

Capture the outputs:

```bash
terraform output -raw state_resource_group_name
terraform output -raw state_storage_account_name
terraform output -raw state_container_name
terraform output -raw init_backend_config_snippet
```

Set the corresponding GitHub Actions repository variables (not secrets — these aren't sensitive):

| Variable | Value |
|---|---|
| `TFSTATE_RESOURCE_GROUP` | `terraform output -raw state_resource_group_name` |
| `TFSTATE_STORAGE_ACCOUNT` | `terraform output -raw state_storage_account_name` |
| `TFSTATE_CONTAINER` | `terraform output -raw state_container_name` |

The bootstrap state file (`terraform.tfstate`) lives **locally** on the operator's machine. Treat it like any other secret: do **not** commit it. The parent `.gitignore` excludes it.

## Why local state for bootstrap?

Chicken-and-egg: storing the bootstrap state in the storage account it just created would prevent the very first `apply`. Local state breaks the loop. Once bootstrap is applied the file is rarely needed again — only when rotating the state SA.
