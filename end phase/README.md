# Phase 10 — GuardDuty to EventBridge to Lambda

This folder contains the Lambda handler, a rollback helper and sanitized configuration templates.

## Files

- `lambda_function.py` — fail-closed handler for the approved GuardDuty EC2 finding types.
- `restore-ec2.ps1` — restores Security Groups from the `SCO-OriginalSecurityGroups` backup tag. It refuses to guess missing IDs and checks that the quarantine SG is attached first.
- `templates/` — placeholder-based examples. Replace all placeholders with values from your own account before deployment.

## Safe deployment defaults

1. Start with Lambda environment `DRY_RUN=true`.
2. Keep the EventBridge production rule disabled until the pattern, target and Lambda resource permission are verified.
3. Test with a GuardDuty sample finding; the handler must log that it skips the sample.
4. Only explicitly opted-in test instances are eligible for live isolation.
5. Before any live test, review the rollback script, IAM policy and network impact. The quarantine Security Group has no ingress or egress and can remove all connectivity.

Never commit account-specific operational JSON, Lambda deployment ZIPs, credentials or secret values. Use IAM roles and a secret store for runtime secrets.
