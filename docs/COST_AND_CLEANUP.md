# AWS cost and cleanup checklist

Stopping EC2 is useful, but it does **not** guarantee that the entire project stops generating charges. Some services are billed for stored data, provisioned capacity, requests, enabled analysis, public IPv4 addresses, or retained resources independently of whether the EC2 instance is running.

## Before leaving the project idle

- [ ] EC2 application instance is stopped if it is not needed for a demo.
- [ ] Check EBS volumes and snapshots; attached volumes can continue to incur storage charges while EC2 is stopped.
- [ ] Check Elastic IPs and public IPv4 allocations; release addresses that are no longer needed only after confirming they are not referenced.
- [ ] Check NAT Gateways; a provisioned NAT Gateway can incur hourly and data-processing charges even when the application is idle.
- [ ] Check RDS instances, ECS services/tasks, load balancers, and other provisioned compute/network resources; stop or delete only after confirming they are not needed and data is backed up.
- [ ] Review CloudFront distributions and WAF web ACLs/rules; requests and configured resources can incur charges. Disable/delete only if no longer needed for the portfolio demonstration.
- [ ] Review GuardDuty, Security Hub and Inspector coverage. These security services can have usage-based charges; decide whether ongoing monitoring is worth the cost for this lab.
- [ ] Review CloudTrail trails/data events and S3 log storage/lifecycle; management events, data events, and log storage can have different cost behavior.
- [ ] Review CloudWatch log groups, retention, metrics and alarms. The Lambda log group was configured with 7-day retention; verify current retention.
- [ ] Confirm the EventBridge rule is `DISABLED` if the automated workflow is not being demonstrated.
- [ ] Keep Lambda `DRY_RUN=true` while the rule is disabled.
- [ ] Review AWS Cost Explorer / Billing by service and set a budget alert for the account.

## Read-only inventory commands

These commands inspect a few known resources; they do not delete or modify anything.

```powershell
$AwsExe = "<AWS_CLI_PATH>"
$Region = "ap-southeast-2"

# EC2 state, network interfaces and attached EBS volume IDs
& $AwsExe ec2 describe-instances `
  --instance-ids <EC2_INSTANCE_ID> `
  --region $Region `
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,PublicIp:PublicIpAddress,Subnet:SubnetId,SGs:SecurityGroups[].GroupId,Volumes:BlockDeviceMappings[].Ebs.VolumeId}' `
  --output table

# NAT Gateways in this region
& $AwsExe ec2 describe-nat-gateways `
  --region $Region `
  --query 'NatGateways[].{Id:NatGatewayId,State:State,Subnet:SubnetId}' `
  --output table

# Elastic IP allocations
& $AwsExe ec2 describe-addresses `
  --region $Region `
  --query 'Addresses[].{AllocationId:AllocationId,PublicIp:PublicIp,AssociationId:AssociationId,NetworkInterfaceId:NetworkInterfaceId}' `
  --output table

# Lambda + EventBridge final state
& $AwsExe lambda get-function-configuration `
  --function-name securecloudops-guardduty-remediation `
  --region $Region `
  --query '{State:State,DRY_RUN:Environment.Variables.DRY_RUN}' `
  --output table

& $AwsExe events describe-rule `
  --name securecloudops-guardduty-remediation-rule `
  --region $Region `
  --query '{Name:Name,State:State}' `
  --output table
```

## Deletion policy

Do not run broad `terraform destroy`, delete the VPC, remove a Security Group, or disable a security service until you have reviewed dependencies, saved evidence, and decided whether the project must remain reproducible. Delete resources in dependency order and preserve the Terraform state/outputs needed to understand what was created.

For a student portfolio, a defensible low-cost approach is usually: keep source code and sanitized evidence in Git; stop the EC2 host when not demoing; remove idle billable resources deliberately; and enable security services only during learning/demo windows if ongoing cost is not justified.
