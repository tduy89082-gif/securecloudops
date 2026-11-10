param(
    [Parameter(Mandatory = $true)]
    [string]$InstanceId,

    [Parameter(Mandatory = $true)]
    [string]$QuarantineSecurityGroupId,

    [string]$Region = "ap-southeast-2",

    [string]$AwsExe = "D:\Project Cloud\securecloudops\CLI\aws.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $AwsExe)) {
    throw "AWS CLI executable not found: $AwsExe"
}

$raw = & $AwsExe ec2 describe-instances `
    --instance-ids $InstanceId `
    --region $Region `
    --output json
if ($LASTEXITCODE -ne 0) { throw "describe-instances failed." }

$data = $raw | ConvertFrom-Json
$instance = @($data.Reservations | ForEach-Object { $_.Instances }) | Select-Object -First 1
if (-not $instance) { throw "EC2 instance was not found: $InstanceId" }

$tagMap = @{}
foreach ($tag in $instance.Tags) { $tagMap[$tag.Key] = $tag.Value }
$originalValue = $tagMap["SCO-OriginalSecurityGroups"]
if ([string]::IsNullOrWhiteSpace($originalValue)) {
    throw "No SCO-OriginalSecurityGroups backup tag exists. Refusing to guess the original Security Groups."
}

$currentGroups = @($instance.NetworkInterfaces[0].Groups | ForEach-Object { $_.GroupId })
if ($currentGroups.Count -ne 1 -or $currentGroups[0] -ne $QuarantineSecurityGroupId) {
    throw "Current Security Groups are not exactly the quarantine group. Inspect the instance manually before restoring. Current: $($currentGroups -join ', ')"
}

$originalGroups = @($originalValue.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries))
if ($originalGroups.Count -lt 1) { throw "Backup tag contains no valid Security Group IDs." }

Write-Host "Instance: $InstanceId"
Write-Host "Quarantine SG: $QuarantineSecurityGroupId"
Write-Host "Restoring original SGs: $($originalGroups -join ', ')"

& $AwsExe ec2 modify-instance-attribute `
    --instance-id $InstanceId `
    --groups $originalGroups `
    --region $Region
if ($LASTEXITCODE -ne 0) { throw "modify-instance-attribute failed. Original backup tag was kept." }

& $AwsExe ec2 create-tags `
    --resources $InstanceId `
    --tags "Key=SCO-RemediationStatus,Value=RESTORED" `
    --region $Region
if ($LASTEXITCODE -ne 0) { throw "Could not set RESTORED status. Original backup tag was kept." }

& $AwsExe ec2 delete-tags `
    --resources $InstanceId `
    --tags "Key=SCO-OriginalSecurityGroups" `
    --region $Region
if ($LASTEXITCODE -ne 0) { throw "Could not remove the backup tag. Review the instance; the SG restore may already have succeeded." }

Write-Host "RESTORE COMPLETE. Verify the instance's Security Groups and application health." -ForegroundColor Green
