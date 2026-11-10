# Portfolio & interview notes

## One-line project summary

**SecureCloudOps** is a cloud-security learning platform that deploys a containerized FastAPI/PostgreSQL workload to AWS and connects threat detection to a guarded, dry-run-first incident-response workflow.

## Resume bullet points (English)

- Built a containerized FastAPI and PostgreSQL workload with Docker Compose, SQLAlchemy and pytest; added a GitHub Actions pipeline for automated tests and Docker image builds.
- Defined an AWS VPC network foundation with Terraform and deployed a Docker Compose workload on EC2, using an instance IAM role and Systems Manager Parameter Store `SecureString` for runtime secrets.
- Configured CloudFront origin verification and AWS security visibility services, including CloudTrail, CloudWatch, GuardDuty, Security Hub and Inspector.
- Implemented a guarded GuardDuty → EventBridge → Lambda response path with sample-finding suppression, account/region/resource validation, explicit opt-in tagging, a deny-all quarantine Security Group and dry-run-first behavior.
- Verified the Phase 10 integration using a GuardDuty sample finding; CloudWatch confirmed the Lambda skipped sample remediation, and the EC2 Security Group remained unchanged.

## Resume bullet points (Vietnamese)

- Xây dựng workload FastAPI/PostgreSQL, đóng gói bằng Docker Compose và viết kiểm thử pytest; thiết lập GitHub Actions để kiểm tra code và build Docker image.
- Dùng Terraform mô tả nền tảng VPC trên AWS, triển khai workload trên EC2 và sử dụng IAM role + Systems Manager Parameter Store SecureString để quản lý secret lúc chạy.
- Cấu hình CloudFront origin verification và các lớp theo dõi/bảo mật gồm CloudTrail, CloudWatch, GuardDuty, Security Hub và Inspector.
- Xây dựng luồng GuardDuty → EventBridge → Lambda với kiểm tra finding, sample suppression, opt-in tag, quarantine Security Group và chế độ DRY_RUN mặc định.

## Demo outline (5–7 minutes)

1. Explain the API workload and show `/docs` and `/health` locally (or use a pre-captured, redacted screenshot if the EC2 host is stopped).
2. Show the VPC design and the Terraform plan/validation evidence.
3. Explain IAM role + Parameter Store secret retrieval without displaying secret values.
4. Show CloudFront origin verification evidence: 403 without the verification header and 200 with it. Never show the token.
5. Show the GuardDuty sample event, EventBridge rule and Lambda CloudWatch log line `GuardDuty sample finding detected. Skipping remediation.`
6. Finish with the safe-state evidence: Lambda dry-run, EventBridge disabled, EC2 stopped, original SG unchanged, no opt-in tag.

## Likely interview questions

**Why use an EC2 role instead of access keys on the server?**

The role provides temporary credentials to the workload and avoids distributing long-lived access keys to the EC2 host. Permissions can be limited to the exact Parameter Store path and required API actions.

**Why keep DRY_RUN enabled?**

It validates decision logic and event delivery without modifying network access. Live quarantine can isolate the host from SSH, SSM dependencies or application traffic, so it needs an approved test plan and tested recovery path.

**Why is the quarantine Security Group empty?**

No inbound and no outbound rules create a simple deny-all isolation state. This is intentionally disruptive and must not be applied to a production instance casually.

**What is not production-ready?**

The current lab has not demonstrated live remediation, high availability, disaster recovery, continuous deployment on every push, full application authentication, database migrations, centralized secrets rotation or comprehensive security scanning. These are future work, not completed claims.

## Evidence checklist

- GitHub Actions run: tests and Docker build green; show the deploy job's actual status.
- Terraform validation and plan summary.
- CloudFront 403/200 origin verification, with token redacted.
- GuardDuty finding + Lambda CloudWatch sample-skip log.
- Final AWS safe-state audit output.
- Redact AWS account IDs, public IPs, key IDs, passwords, token values and personal email addresses in screenshots.
