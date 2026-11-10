# Terraform network foundation

This is a clean, parameterized network reference matching the SecureCloudOps lab topology: one VPC, two public subnets, two private subnets, an Internet Gateway and separate route tables/associations. It intentionally does **not** create a NAT Gateway to avoid recurring hourly charges. Private subnets therefore have no default internet egress in this baseline.

## Important before use

- This configuration is a reusable reference for a **new** network. It is not the exported Terraform state of the existing AWS environment.
- Do not run `terraform apply` against an account with existing resources until you have reviewed `terraform plan` and decided whether to create a separate VPC or import existing resources.
- Terraform state, provider binaries and `.terraform/` are intentionally excluded from Git.
- Use an IAM identity with least privilege; prefer short-lived credentials/roles, never commit access keys.

## Commands

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Review the plan carefully. `terraform apply` is intentionally not included in the project quickstart.
