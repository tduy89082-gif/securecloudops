# Phase 6 — IAM Least Privilege & Secrets Management

## 1. Objectives

This phase improves the security of the SecureCloudOps deployment by:

- Assigning an IAM role to the EC2 instance instead of storing AWS access keys on the server.
- Storing the database password in AWS Systems Manager Parameter Store as a `SecureString`.
- Restricting the EC2 role to retrieving the required database parameter.
- Passing the database password to Docker Compose through environment variables instead of hardcoding it in the deployment configuration.
- Verifying access permissions and application health.

## 2. AWS Resources

| Resource | Configuration |
|---|---|
| EC2 IAM role | `securecloudops-ec2-secrets-role` |
| IAM policy | `SecureCloudOpsReadDatabasePassword` |
| Parameter Store path | `/securecloudops/dev/database/password` |
| Parameter type | `SecureString` |
| Parameter tier | Standard |
| KMS key | AWS-managed key `alias/aws/ssm` |
| AWS Region | `ap-southeast-2` |

Secret values and credentials are intentionally excluded from this documentation.

## 3. IAM Access Control

The EC2 role is intended to have permission to call `ssm:GetParameter` on the specific database password parameter.

The role is not intended to have broad Parameter Store permissions such as `ssm:GetParametersByPath`.

This follows the principle of least privilege: workloads should receive only the permissions required for their tasks.

## 4. Secret Retrieval Flow

1. EC2 obtains temporary AWS credentials through its attached IAM role.
2. The instance retrieves the required parameter using AWS Systems Manager Parameter Store.
3. Parameter Store returns the decrypted `SecureString` value to the authorized workload.
4. The deployment shell exports the value as `POSTGRES_PASSWORD`.
5. The shell constructs `DATABASE_URL` and supplies both variables to Docker Compose.
6. PostgreSQL and the FastAPI service start using the supplied configuration.

The secret is not intentionally printed to the terminal or stored in the Docker Compose YAML as a literal value.

## 5. Verification Results

| Test | Expected result | Observed result |
|---|---|---|
| `aws sts get-caller-identity` | EC2 assumes the intended role | Passed |
| Retrieve the parameter and query its type | `SecureString` | Passed |
| `docker compose config --quiet` | Configuration validates | Passed |
| `docker compose ps` | API running; database healthy | Passed |
| `curl -i http://localhost:8000/health` | HTTP 200 | Passed |
| `curl -i http://localhost:8000/tasks` | HTTP 200 and task data | Passed |
| `ssm:GetParametersByPath` against `/securecloudops/dev` | Access denied | Passed |

The denied `GetParametersByPath` request confirms that the tested role was not granted that action for the requested path.

## 6. Security Considerations and Limitations

- The parameter value is encrypted using the AWS-managed `alias/aws/ssm` KMS key. AWS documents that this default key does not provide the same per-role decryption restrictions as a customer-managed KMS key.
- Environment variables reduce the need to hardcode credentials in configuration files, but privileged users with access to Docker or the EC2 host may still be able to inspect container configuration or environment variables.
- The secret retrieval shown in this phase was performed in an interactive SSH shell. The exported variables do not automatically persist into a new shell session.
- Automated secret retrieval after a host reboot or application restart has not yet been configured.
- The local development configuration and the repository must also be checked to ensure that no literal password is committed to Git.
- This deployment is a learning environment, not a complete production secrets-management solution.

## 7. Future Improvements

- Synchronize and review the local Docker Compose configuration.
- Keep local environment files out of version control.
- Implement a controlled startup mechanism that retrieves the secret without writing it into the repository.
- Add CloudTrail-based auditing and review IAM permissions regularly.
- Evaluate a customer-managed KMS key if stricter decryption authorization becomes necessary.

## 8. Official References

- [AWS Systems Manager Parameter Store — Setting up permissions](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store-setting-up.html)
- [AWS Systems Manager — Restricting access to parameters](https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-restrict-parameter-access.html)
- [AWS Systems Manager — Restricting decryption of SecureString parameters](https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-restrict-decryption.html)
    