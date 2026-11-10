"""SecureCloudOps Phase 10: guarded GuardDuty -> EventBridge -> Lambda EC2 quarantine.

Only the approved GuardDuty finding types and explicitly opted-in EC2 instances are
eligible. The function fails closed and supports DRY_RUN=true for safe testing.
"""
from __future__ import annotations

import logging
import os
import json
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)

EC2 = boto3.client("ec2")

ALLOWED_FINDING_TYPES = {
    "UnauthorizedAccess:EC2/TorClient",
    "UnauthorizedAccess:EC2/TorRelay",
}

OPT_IN_TAG = "SecureCloudOpsAutoRemediate"
ORIGINAL_GROUPS_TAG = "SCO-OriginalSecurityGroups"
STATUS_TAG = "SCO-RemediationStatus"


def _response(status: str, message: str, **details: Any) -> dict[str, Any]:
    result: dict[str, Any] = {"status": status, "message": message}
    result.update(details)
    return result


def _tag_map(tags: list[dict[str, str]]) -> dict[str, str]:
    return {tag.get("Key", ""): tag.get("Value", "") for tag in tags}


def _is_sample_finding(detail: dict[str, Any]) -> bool:
    """Detect GuardDuty sample findings using supported finding fields."""

    # GuardDuty sample findings have a [SAMPLE] title prefix.
    title = str(detail.get("title") or "")
    if title.upper().startswith("[SAMPLE]"):
        return True

    service = detail.get("service") or {}

    additional_info_candidates = [
        detail.get("additionalInfo"),
        service.get("additionalInfo")
        if isinstance(service, dict)
        else None,
    ]

    for info in additional_info_candidates:
        if not isinstance(info, dict):
            continue

        # Support direct sample boolean/string representation.
        sample_flag = info.get("sample")
        if str(sample_flag).lower() == "true":
            return True

        # GuardDuty ServiceAdditionalInfo.value can contain JSON text.
        value = info.get("value")

        if isinstance(value, dict):
            parsed_value = value
        elif isinstance(value, str):
            try:
                parsed_value = json.loads(value)
            except (json.JSONDecodeError, TypeError):
                parsed_value = {}
        else:
            parsed_value = {}

        if (
            isinstance(parsed_value, dict)
            and str(parsed_value.get("sample", "")).lower() == "true"
        ):
            return True

    return False



def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Validate a GuardDuty event and quarantine one opted-in EC2 instance."""
    expected_account = os.environ["EXPECTED_ACCOUNT_ID"]
    expected_region = os.environ["EXPECTED_REGION"]
    expected_vpc = os.environ["EXPECTED_VPC_ID"]
    expected_instance_id = os.environ["TARGET_INSTANCE_ID"]
    quarantine_sg = os.environ["QUARANTINE_SG_ID"]
    dry_run = os.environ.get("DRY_RUN", "true").strip().lower() == "true"

    # 1. Validate the event envelope and the precise finding type.
    if event.get("source") != "aws.guardduty":
        return _response("SKIPPED", "Event source is not aws.guardduty")
    if event.get("detail-type") != "GuardDuty Finding":
        return _response("SKIPPED", "Event is not a GuardDuty Finding")
    if event.get("account") != expected_account or event.get("region") != expected_region:
        return _response("SKIPPED", "Event account or region does not match configuration")

    detail = event.get("detail") or {}
    if detail.get("accountId") != expected_account:
        return _response("SKIPPED", "Finding accountId does not match configuration")

    finding_type = detail.get("type", "")
    if finding_type not in ALLOWED_FINDING_TYPES:
        return _response("SKIPPED", "Finding type is not approved", finding_type=finding_type)

    try:
        severity = float(detail.get("severity", 0))
    except (TypeError, ValueError):
        return _response("SKIPPED", "Finding severity is missing or invalid")
    if severity < 4.0:
        return _response("SKIPPED", "Finding severity is below the configured threshold", severity=severity)


    if _is_sample_finding(detail):
        LOG.warning("GuardDuty sample finding detected. Skipping remediation.")
        return _response(
            "SKIPPED",
            "GuardDuty sample finding; no resource changes are made",
        )


    resource = detail.get("resource") or {}
    if resource.get("resourceType") != "Instance":
        return _response("SKIPPED", "Finding resource is not an EC2 Instance")

    instance_details = resource.get("instanceDetails") or {}
    instance_id = instance_details.get("instanceId", "")
    if not isinstance(instance_id, str) or not instance_id.startswith("i-"):
        return _response("SKIPPED", "Finding does not contain a valid EC2 instance ID")

    if instance_id != expected_instance_id:
     return _response(
        "SKIPPED",
        "Instance is not the approved SecureCloudOps target",
        instance_id=instance_id,
    )

    LOG.info(
        "Processing finding_id=%s finding_type=%s severity=%s instance_id=%s dry_run=%s",
        detail.get("id", "unknown"), finding_type, severity, instance_id, dry_run,
    )

    # 2. Confirm the instance exists and belongs to the intended VPC.
    response = EC2.describe_instances(InstanceIds=[instance_id])
    reservations = response.get("Reservations", [])
    instances = [instance for reservation in reservations for instance in reservation.get("Instances", [])]
    if len(instances) != 1:
        return _response("SKIPPED", "EC2 instance was not found uniquely", instance_id=instance_id)

    instance = instances[0]
    state = (instance.get("State") or {}).get("Name", "unknown")
    if state not in {"running", "stopped"}:
     return _response(
        "SKIPPED",
        "EC2 instance is not in an eligible state",
        instance_id=instance_id,
        state=state,
    )
    if instance.get("VpcId") != expected_vpc:
        return _response("SKIPPED", "EC2 instance is outside the approved VPC", instance_id=instance_id)

    # ModifyInstanceAttribute can fail for instances with multiple ENIs.
    network_interfaces = instance.get("NetworkInterfaces", [])
    if len(network_interfaces) != 1:
        return _response(
            "SKIPPED", "Expected exactly one network interface; manual review required",
            instance_id=instance_id, network_interface_count=len(network_interfaces),
        )

    tags = _tag_map(instance.get("Tags", []))
    if tags.get(OPT_IN_TAG, "").lower() != "true":
        return _response("SKIPPED", "Instance has not opted in to automatic remediation", instance_id=instance_id)

    current_groups = sorted({group["GroupId"] for group in network_interfaces[0].get("Groups", []) if group.get("GroupId")})
    if not current_groups:
        return _response("SKIPPED", "Instance has no readable security groups", instance_id=instance_id)

    # 3. Fail closed if the quarantine group is missing, in another VPC, or has rules.
    sg_response = EC2.describe_security_groups(GroupIds=[quarantine_sg])
    security_groups = sg_response.get("SecurityGroups", [])
    if len(security_groups) != 1:
        raise RuntimeError("Configured quarantine Security Group was not found uniquely")
    quarantine = security_groups[0]
    if quarantine.get("VpcId") != expected_vpc:
        raise RuntimeError("Quarantine Security Group is not in the approved VPC")
    if quarantine.get("IpPermissions") or quarantine.get("IpPermissionsEgress"):
        raise RuntimeError("Quarantine Security Group must have zero inbound and zero outbound rules")

    if quarantine_sg in current_groups:
        return _response("ALREADY_QUARANTINED", "Quarantine Security Group is already attached", instance_id=instance_id)

    if tags.get(ORIGINAL_GROUPS_TAG):
        return _response(
            "SKIPPED", "A previous original-Security-Group backup tag exists; inspect or restore manually first",
            instance_id=instance_id,
        )

    if dry_run:
        LOG.info(
            "DRY_RUN: would replace instance %s security groups %s with %s",
            instance_id, current_groups, quarantine_sg,
        )
        return _response(
            "DRY_RUN", "All checks passed; no AWS resources were changed",
            instance_id=instance_id, original_security_groups=current_groups,
            quarantine_security_group=quarantine_sg, finding_type=finding_type,
        )

    # 4. Save rollback data BEFORE changing the instance networking.
    finding_id = str(detail.get("id", "unknown"))[:256]
    finding_type_tag = finding_type[:256]
    pending_tags = [
        {"Key": ORIGINAL_GROUPS_TAG, "Value": ",".join(current_groups)[:256]},
        {"Key": STATUS_TAG, "Value": "QUARANTINE_PENDING"},
        {"Key": "SCO-LastFindingId", "Value": finding_id},
        {"Key": "SCO-LastFindingType", "Value": finding_type_tag},
    ]
    EC2.create_tags(Resources=[instance_id], Tags=pending_tags)

    try:
        # This replaces, rather than adds to, the existing security groups.
        EC2.modify_instance_attribute(InstanceId=instance_id, Groups=[quarantine_sg])
    except ClientError:
        EC2.create_tags(Resources=[instance_id], Tags=[{"Key": STATUS_TAG, "Value": "QUARANTINE_FAILED"}])
        LOG.exception("Failed to apply quarantine Security Group to %s", instance_id)
        raise

    quarantined_at = datetime.now(timezone.utc).isoformat()
    EC2.create_tags(
        Resources=[instance_id],
        Tags=[
            {"Key": STATUS_TAG, "Value": "QUARANTINED"},
            {"Key": "SCO-QuarantinedAt", "Value": quarantined_at},
        ],
    )

    LOG.warning(
        "QUARANTINED instance_id=%s finding_id=%s original_groups=%s quarantine_sg=%s",
        instance_id, finding_id, current_groups, quarantine_sg,
    )
    return _response(
        "QUARANTINED", "EC2 security groups replaced with the quarantine Security Group",
        instance_id=instance_id, original_security_groups=current_groups,
        quarantine_security_group=quarantine_sg, finding_id=finding_id,
    )
