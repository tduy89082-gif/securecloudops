# Test evidence and acceptance record

This record captures outcomes explicitly observed during the project. Re-run tests before presenting a fresh live demo because AWS resource states can change.

| Test | Expected | Observed result | Status |
|---|---|---|---|
| Local API health | `GET /health` returns HTTP 200 | Local API was exercised through `/docs`; deployed EC2 `/health` previously returned HTTP 200 | PASS (at time tested) |
| CloudFront origin verification — no token | Reject direct/unverified request | HTTP 403 | PASS |
| CloudFront origin verification — valid token | Accept request | HTTP 200 | PASS |
| Terraform validation | `terraform validate` succeeds | Passed | PASS |
| Terraform plan | No unexpected drift | `No changes` at the time checked | PASS (at time tested) |
| Lambda direct sample event | Skip sample, no changes | `status=SKIPPED` | PASS |
| Lambda direct eligible synthetic event | With valid checks and `DRY_RUN=true`, report dry run | `status=DRY_RUN`; no AWS resources changed | PASS |
| EventBridge pattern positive case | Matching TorClient/TorRelay finding with severity threshold matches | `Result: True` | PASS |
| EventBridge pattern negative case | Non-allowed finding type does not match | PortProbe returned `Result: False` | PASS |
| GuardDuty sample integration | Sample reaches Lambda and is skipped | CloudWatch contained `GuardDuty sample finding detected. Skipping remediation.` | PASS |
| Post-test safety | No network change or opt-in tag remains | EC2 stopped; original SG unchanged; `SameSecurityGroups=True`; opt-in tag count 0 | PASS |
| Post-test EventBridge state | Rule disabled and production pattern restored | `DISABLED`; `put-rule` returned rule ARN | PASS |

## Evidence that should be captured for the GitHub repository

1. Screenshot of `terraform validate` and the successful `terraform plan` summary (remove account IDs and sensitive paths if desired).
2. GitHub Actions run showing the CI test and Docker build jobs completed successfully. Keep the SSM/EC2 deployment job's conditional/skip status visible and explain it honestly.
3. CloudFront verification output showing 403 without the origin token and 200 with it. Never include the actual secret token in screenshots or logs.
4. GuardDuty sample finding event and the corresponding Lambda CloudWatch log line proving the sample was skipped.
5. Final-state output proving EventBridge disabled, Lambda dry-run enabled, EC2 stopped, original SG unchanged, and no opt-in tag.
6. Security Group details showing the quarantine SG has zero ingress and zero egress rules.

## Evidence handling

- Redact AWS account IDs, public IPs, access-key material, private-key contents, session tokens, database passwords, origin-verification values, and any personal email address.
- Do not upload PEM keys, `.env`, Terraform state, CloudWatch logs containing secrets, or raw credentials.
- Keep timestamps and command outcomes so reviewers can understand what was actually tested.
