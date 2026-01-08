# Repository Guidelines

## Project Structure & Module Organization
Terraform IaC lives in `baseline/` (shared Azure resources) and `infra/` (ACI, ACR, Key Vault wiring); run Terraform from the folder that matches the layer you are touching. The Snowflake dbt project sits in `tpch_transform/` where `models/`, `macros/`, `analyses/`, `seeds/`, `snapshots/`, and `tests/` follow `dbt_project.yml`, and Docker assets (`Dockerfile`, `entrypoint.sh`, `Makefile`) bundle the workload for Azure Container Instances. Architecture diagrams in `images/` are handy context for PR reviewers.

## Build, Test, and Development Commands
- `cd baseline && terraform init && terraform plan -out baseline.tfplan`: stage backbone resources; apply with `terraform apply baseline.tfplan`.
- `cd infra && terraform plan`: reconcile compute, registry, and secret plumbing before each deployment.
- `cd tpch_transform && make build DOCKER_VERSION=$(git rev-parse --short HEAD)` followed by `make push`: build and publish the linux/amd64 dbt container to `dbtjobs.azurecr.io`.
- `cd tpch_transform && dbt deps && dbt build --select +models.stg_orders`: install packages and run seeds, models, and tests locally with the Snowflake profile defined in `profiles.yml`.

## Coding Style & Naming Conventions
Use two-space SQL/Jinja indentation and snake_case model names (`stg_orders`, `dim_customer`) so dbt selectors remain predictable. Macro names should describe their intent (`generate_surrogate_key`), and snapshot/seeds should mirror Snowflake schema names. Keep Terraform blocks ordered by resource type and run `terraform fmt` before committing. Make/Docker targets stay lowercase verbs (`build`, `push`) per the existing Makefile.

## Testing Guidelines
Favor `dbt build` for end-to-end validation, then tighten feedback with `dbt test --select tests.not_null_orders_orderkey` when iterating. Declare schema tests beside each model YAML and reserve the `tests/` directory for more complex SQL. Refresh fixtures via `dbt seed` whenever TPCH CSVs change so CI and local runs stay deterministic.

## Commit & Pull Request Guidelines
Git history shows short imperative messages (“Initial commit”); continue that pattern (`Add models for tpch supplier`) and reference Azure or GitHub issues in the body. Call out Terraform state impacts, list commands executed (`terraform plan`, `dbt build`), and attach screenshots or plan snippets when visuals help. Request reviewers from both data and platform teams whenever a change spans dbt plus IaC.

## Security & Configuration Tips
`profiles.yml` is illustrative only—load Snowflake secrets from Azure Key Vault or CI variables and mount the private key path during container launch. Limit local work to dev-grade roles instead of `ACCOUNTADMIN`, lock Terraform backends before `apply`, and rotate ACR/Key Vault credentials whenever you publish new runtime images or rotate dbt service keys.
