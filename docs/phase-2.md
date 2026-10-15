# Phase 2 — AWS Networking

## Objective

Build a secure AWS network foundation for SecureCloudOps.

The application is still the same workload created in Phase 1.
Phase 2 focuses only on AWS networking.

## Target architecture

```text
                         INTERNET
                             |
                    Internet Gateway
                             |
                     +-------+-------+
                     |      VPC      |
                     | 10.0.0.0/16   |
                     |               |
              +------+-------+-------+------+
              |              |              |
            AZ-A           AZ-A           AZ-B
              |              |              |
         Public-A       Private-A       Public-B
       10.0.1.0/24    10.0.11.0/24    10.0.2.0/24
              |              |
          NAT Gateway     Future ECS
                             |
                         Future RDS

                         Private-B
                       10.0.12.0/24

# Phase 2 — AWS Networking

## VPC

Name: securecloudops-vpc
CIDR: 10.0.0.0/16

## Subnets

Public A: 10.0.1.0/24
Public B: 10.0.2.0/24

Private A: 10.0.11.0/24
Private B: 10.0.12.0/24

## Internet Gateway

Name: securecloudops-igw

## Route Tables

### Public

10.0.0.0/16 -> local
0.0.0.0/0 -> Internet Gateway

### Private

10.0.0.0/16 -> local
No Internet route

## Security Groups

ALB:
80/443 from Internet

Application:
8000 from ALB Security Group

Database:
5432 from Application Security Group

## Cost Control

NAT Gateway was not created.
EC2, ECS, RDS and ALB were not created.

## Status

- [x] VPC
- [x] 4 Subnets
- [x] Internet Gateway
- [x] Public Route Table
- [x] Private Route Table
- [x] Security Groups
- [x] No NAT Gateway