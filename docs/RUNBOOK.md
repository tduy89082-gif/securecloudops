# Operations runbook

This runbook describes the verified safe state and the standard operator checks. Commands are for Windows PowerShell and use the AWS CLI executable path that was working in the project environment.

## 1. Load variables

```powershell
$AwsExe = "<AWS_CLI_PATH>"
$Region = "ap-southeast-2"
$AccountId = "<AWS_ACCOUNT_ID>"
$InstanceId = "<EC2_INSTANCE_ID>"
$FunctionName = "securecloudops-guardduty-remediation"
$RuleName = "securecloudops-guardduty-remediation-rule"
$QuarantineSgId = "<QUARANTINE_SG_ID>"
$OriginalSgId = "<ORIGINAL_SG_ID>"
$LogGroup = "/aws/lambda/securecloudops-guardduty-remediation"
```

## 2. Verify identity before making changes

```powershell
& $AwsExe sts get-caller-identity --output json
```

Confirm the account is `<AWS_ACCOUNT_ID>`. Stop if the account or role/user is unexpected.

## 3. Check the verified safe state

```powershell
$Lambda = (& $AwsExe lambda get-function-configuration `
  --function-name $FunctionName --region $Region --output json) | ConvertFrom-Json

$Rule = (& $AwsExe events describe-rule `
  --name $RuleName --region $Region --output json) | ConvertFrom-Json

$Targets = (& $AwsExe events list-targets-by-rule `
  --rule $RuleName --region $Region --output json) | ConvertFrom-Json

$Ec2Response = (& $AwsExe ec2 describe-instances `
  --instance-ids $InstanceId --region $Region --output json) | ConvertFrom-Json
$Instance = $Ec2Response.Reservations | ForEach-Object { $_.Instances } | Select-Object -First 1

[PSCustomObject]@{
  LambdaState = $Lambda.State
  DryRun = $Lambda.Environment.Variables.DRY_RUN
  EventBridgeState = $Rule.State
  TargetCount = $Targets.Targets.Count
  InstanceState = $Instance.State.Name
  SecurityGroups = ($Instance.SecurityGroups.GroupId -join ", ")
  OptInTag = (($Instance.Tags | Where-Object { $_.Key -eq "SecureCloudOpsAutoRemediate" }).Value -join ", ")
} | Format-List
```

Expected after the completed integration test: Lambda `Active`, `DRY_RUN=true`, EventBridge `DISABLED`, one target, EC2 `stopped`, original SG attached, and no opt-in tag.

## 4. Inspect Lambda logs

```powershell
& $AwsExe logs filter-log-events `
  --log-group-name $LogGroup `
  --region $Region `
  --limit 50 `
  --output json
```

Look for the sample skip message, `SKIPPED`, `DRY_RUN`, exceptions, and Lambda `START`/`END`/`REPORT` records. Do not treat the presence of a `START` record alone as proof that remediation logic passed its checks.

## 5. Review the quarantine Security Group

```powershell
& $AwsExe ec2 describe-security-groups `
  --group-ids $QuarantineSgId `
  --region $Region `
  --query 'SecurityGroups[0].{Id:GroupId,Vpc:VpcId,Ingress:IpPermissions,Egress:IpPermissionsEgress}' `
  --output json
```

The verified quarantine group had no ingress and no egress rules. Confirm the VPC matches the target instance before any use.

## 6. Rollback principle

If live isolation has been performed, do not guess the original group IDs. Read the instance tag `SCO-OriginalSecurityGroups`, validate the IDs and their VPC, and restore only after an operator has confirmed the incident is contained. Then remove the rollback tag and remediation status tags according to the Lambda implementation. Keep an audit record of who authorized the action and when.

A conceptual rollback command (run only after validating the exact saved IDs):

```powershell
# Example only — replace with the exact saved SG IDs after review.
# Do not run this command against the current safe/demo instance.
# & $AwsExe ec2 modify-instance-attribute --instance-id $InstanceId --groups sg-xxxxxxxx sg-yyyyyyyy --region $Region
```

## 7. Never do these during a demo

- Do not change `DRY_RUN` to `false` just to make the demo look complete.
- Do not enable the production EventBridge rule without an approved test window and rollback plan.
- Do not add the opt-in tag to a shared or production instance casually.
- Do not attach the quarantine SG to the instance manually as a test; it has no ingress or egress.
- Do not delete the original SG while it may be needed for rollback.


## Run the read-only final audit script

From the repository root, supply the identifiers from your own AWS account. Do not store them in the repository:

```powershell
$AwsExe = "D:\Project Cloud\securecloudops\CLI\aws.exe"
.\scripts\verify-aws-final-state.ps1 `
  -AwsExe $AwsExe `
  -ExpectedAccountId "YOUR_ACCOUNT_ID" `
  -InstanceId "YOUR_EC2_INSTANCE_ID" `
  -ExpectedVpcId "YOUR_VPC_ID" `
  -OriginalSecurityGroupId "YOUR_ORIGINAL_SG_ID" `
  -QuarantineSecurityGroupId "YOUR_QUARANTINE_SG_ID"
```

The script only calls STS `GetCallerIdentity`, Lambda `GetFunctionConfiguration`, EventBridge `DescribeRule`/`ListTargetsByRule`, and EC2 `DescribeInstances`/`DescribeSecurityGroups`. It is read-only.
