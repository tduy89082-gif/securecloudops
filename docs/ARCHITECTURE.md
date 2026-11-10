# Architecture and design

## Logical view

```mermaid
flowchart TB
    subgraph Edge[Edge layer]
      Client[API consumer]
      WAF[AWS WAF]
      CF[CloudFront distribution]
      Client --> CF
      WAF -. Web ACL association .-> CF
    end

    subgraph Network[AWS VPC]
      IGW[Internet Gateway]
      subgraph Public[Public subnet tier]
        EC2[EC2 application host]
      end
      subgraph Workload[Container workload]
        API[FastAPI]
        DB[(PostgreSQL)]
        API --> DB
      end
      EC2 --> API
      IGW --> EC2
    end
    CF -->|origin request with secret verification header| EC2

    subgraph Identity[Identity and secrets]
      Role[EC2 IAM role]
      SSM[Systems Manager Parameter Store SecureString]
      KMS[KMS key]
      Role --> SSM
      KMS --> SSM
    end
    Role -. permissions .-> EC2

    subgraph Detection[Detection and response]
      GD[GuardDuty]
      EB[EventBridge rule]
      L[Lambda validation/remediation]
      QSG[Quarantine Security Group]
      GD --> EB --> L --> QSG
      L -. inspect / optionally update .-> EC2
    end

    CT[CloudTrail] --> CW[CloudWatch Logs]
    L --> CW
    SH[Security Hub] --> Review[Security findings review]
    INS[Inspector] --> Review
```

## Network model

- VPC CIDR: `10.0.0.0/16`.
- The Terraform design contains two public and two private subnet resources with route tables and an Internet Gateway.
- Workload instance: `<EC2_INSTANCE_ID>`, VPC `<VPC_ID>`, subnet `subnet-079d1049aa6e8f60e`.
- Do not infer that private workloads are currently deployed merely because private subnets exist in Terraform.
- The instance security group previously included SSH ingress and application ingress. Restrict SSH to a trusted CIDR before restarting or exposing the host.

## Trust boundaries

1. **Internet → CloudFront:** public entry point; WAF is intended to inspect/filter requests.
2. **CloudFront → origin:** origin verification header is used to prevent direct requests that lack the expected token. The observed test was 403 without the token and 200 with it.
3. **EC2 → AWS APIs:** use the instance role and Parameter Store rather than embedding long-lived credentials or passwords in the image.
4. **GuardDuty → EventBridge:** the production event pattern limits the trigger to the expected account, finding types/severity and target EC2 instance.
5. **EventBridge → Lambda:** Lambda resource policy permits the specified EventBridge rule to invoke the function.
6. **Lambda → EC2:** fail-closed checks and the `SecureCloudOpsAutoRemediate=true` opt-in tag gate the potential network isolation operation.

## Phase 10 decision sequence

```mermaid
flowchart TD
    A[Receive GuardDuty event] --> B{Account and region expected?}
    B -- No --> S[Skip]
    B -- Yes --> C{Allowed EC2 finding type and severity?}
    C -- No --> S
    C -- Yes --> D{Sample finding?}
    D -- Yes --> S
    D -- No --> E{Target instance and expected VPC?}
    E -- No --> S
    E -- Yes --> F{Exactly one ENI and valid quarantine SG?}
    F -- No --> S
    F -- Yes --> G{Opt-in tag true?}
    G -- No --> S
    G -- Yes --> H{DRY_RUN true?}
    H -- Yes --> I[Log DRY_RUN; no mutation]
    H -- No --> J[Save original SG IDs in rollback tag]
    J --> K[Replace SG with quarantine SG]
```

## Important design choices

- **Opt-in, not opt-out:** only explicitly tagged instances are eligible for remediation.
- **Sample findings are skipped:** sample events validate integration without isolating a host.
- **Dry-run default:** lets the team validate event delivery and guard conditions without changing networking.
- **Dedicated quarantine SG:** zero ingress and zero egress is a clear deny-all isolation profile.
- **Rollback metadata:** the function records original security-group IDs before switching the instance to quarantine.

## Current architecture boundary

The current verified workload is EC2 with Docker Compose containers, not a confirmed ECS/RDS production deployment. Keep diagrams and interview descriptions aligned with the resources actually provisioned in the account.
