<#
.SYNOPSIS
  Read-only final-state audit for the SecureCloudOps Phase 10 demo environment.
.DESCRIPTION
  Checks AWS identity, Lambda DRY_RUN, the disabled production EventBridge rule,
  its Lambda target, the EC2 instance and the deny-all quarantine Security Group.
  This script calls read-only AWS APIs only; it does not modify AWS resources.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExpectedAccountId,
    [Parameter(Mandatory)][string]$InstanceId,
    [Parameter(Mandatory)][string]$ExpectedVpcId,
    [Parameter(Mandatory)][string]$OriginalSecurityGroupId,
    [Parameter(Mandatory)][string]$QuarantineSecurityGroupId,
    [string]$Region = 'ap-southeast-2',
    [string]$FunctionName = 'securecloudops-guardduty-remediation',
    [string]$RuleName = 'securecloudops-guardduty-remediation-rule',
    [string]$AwsExe = 'aws'
)

$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

function Invoke-AwsJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & $AwsExe @Arguments --no-cli-pager --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI failed ($LASTEXITCODE): $($Arguments -join ' ')`n$($output -join "`n")"
    }
    $joined = $output -join "`n"
    if ([string]::IsNullOrWhiteSpace($joined)) { return $null }
    return $joined | ConvertFrom-Json
}

function Add-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Detail
    )
    $checks.Add([PSCustomObject]@{
        Check = $Name
        Result = if ($Passed) { 'PASS' } else { 'FAIL' }
        Detail = $Detail
    })
    if (-not $Passed) { $failures.Add($Name) }
}

if (-not (Test-Path -LiteralPath $AwsExe)) {
    # Permit PATH resolution when the caller supplies the command name 'aws'.
    if ($AwsExe -ne 'aws' -or -not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw "AWS CLI executable/command not found: $AwsExe"
    }
}

$identity = Invoke-AwsJson -Arguments @('sts','get-caller-identity','--region',$Region)
Add-Check -Name 'AWS account' -Passed ($identity.Account -eq $ExpectedAccountId) -Detail "Account=$($identity.Account); expected=$ExpectedAccountId"

$lambda = Invoke-AwsJson -Arguments @('lambda','get-function-configuration','--function-name',$FunctionName,'--region',$Region)
$dryRun = $lambda.Environment.Variables.DRY_RUN
$lambdaPass = ($lambda.State -eq 'Active') -and ($lambda.LastUpdateStatus -eq 'Successful') -and ($dryRun -eq 'true')
Add-Check -Name 'Lambda safe mode' -Passed $lambdaPass -Detail "State=$($lambda.State); LastUpdate=$($lambda.LastUpdateStatus); DRY_RUN=$dryRun"

$rule = Invoke-AwsJson -Arguments @('events','describe-rule','--name',$RuleName,'--region',$Region)
$pattern = $rule.EventPattern | ConvertFrom-Json
$allowedTypes = @('UnauthorizedAccess:EC2/TorClient','UnauthorizedAccess:EC2/TorRelay')
$patternPass = (@($pattern.source) -contains 'aws.guardduty') -and
    (@($pattern.'detail-type') -contains 'GuardDuty Finding') -and
    (@($pattern.account) -contains $ExpectedAccountId) -and
    (@($pattern.detail.accountId) -contains $ExpectedAccountId) -and
    (@($pattern.detail.type | Where-Object { $_ -in $allowedTypes }).Count -eq 2) -and
    (@($pattern.detail.resource.resourceType) -contains 'Instance') -and
    (@($pattern.detail.resource.instanceDetails.instanceId) -contains $InstanceId)
Add-Check -Name 'Production EventBridge pattern' -Passed $patternPass -Detail "Account and target filters match expected values: $patternPass"
Add-Check -Name 'EventBridge disabled' -Passed ($rule.State -eq 'DISABLED') -Detail "State=$($rule.State)"

$targets = Invoke-AwsJson -Arguments @('events','list-targets-by-rule','--rule',$RuleName,'--region',$Region)
$expectedLambdaArn = "arn:aws:lambda:${Region}:${ExpectedAccountId}:function:${FunctionName}"
$targetPass = ($targets.Targets.Count -eq 1) -and ($targets.Targets[0].Arn -eq $expectedLambdaArn)
Add-Check -Name 'EventBridge Lambda target' -Passed $targetPass -Detail "TargetCount=$($targets.Targets.Count); ExpectedLambdaTarget=$targetPass"

$ec2 = Invoke-AwsJson -Arguments @('ec2','describe-instances','--instance-ids',$InstanceId,'--region',$Region)
$instance = $ec2.Reservations | ForEach-Object { $_.Instances } | Select-Object -First 1
if ($null -eq $instance) { throw "Instance not found: $InstanceId" }
$groupIds = @($instance.SecurityGroups | ForEach-Object { $_.GroupId })
Add-Check -Name 'EC2 stopped' -Passed ($instance.State.Name -eq 'stopped') -Detail "State=$($instance.State.Name)"
Add-Check -Name 'Original Security Group attached' -Passed ($groupIds -contains $OriginalSecurityGroupId) -Detail "OriginalGroupAttached=$($groupIds -contains $OriginalSecurityGroupId)"
Add-Check -Name 'EC2 expected VPC' -Passed ($instance.VpcId -eq $ExpectedVpcId) -Detail "VPCMatchesExpected=$($instance.VpcId -eq $ExpectedVpcId)"
$optIn = @($instance.Tags | Where-Object { $_.Key -eq 'SecureCloudOpsAutoRemediate' })
$backup = @($instance.Tags | Where-Object { $_.Key -eq 'SCO-OriginalSecurityGroups' })
Add-Check -Name 'No remediation/rollback tags' -Passed (($optIn.Count -eq 0) -and ($backup.Count -eq 0)) -Detail "OptInTagCount=$($optIn.Count); RollbackTagCount=$($backup.Count)"

$qResponse = Invoke-AwsJson -Arguments @('ec2','describe-security-groups','--group-ids',$QuarantineSecurityGroupId,'--region',$Region)
$qsg = $qResponse.SecurityGroups | Select-Object -First 1
if ($null -eq $qsg) { throw "Quarantine Security Group not found: $QuarantineSecurityGroupId" }
$qIngressCount = @($qsg.IpPermissions).Count
$qEgressCount = @($qsg.IpPermissionsEgress).Count
$qPass = ($qsg.VpcId -eq $ExpectedVpcId) -and ($qIngressCount -eq 0) -and ($qEgressCount -eq 0)
Add-Check -Name 'Quarantine SG deny-all profile' -Passed $qPass -Detail "VpcMatchesExpected=$($qsg.VpcId -eq $ExpectedVpcId); IngressRules=$qIngressCount; EgressRules=$qEgressCount"

$checks | Format-Table -AutoSize -Wrap
if ($failures.Count -gt 0) {
    Write-Host "`nFINAL AUDIT: FAIL — $($failures -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "`nFINAL AUDIT: PASS — safe demo state verified. No AWS resources were modified." -ForegroundColor Green
