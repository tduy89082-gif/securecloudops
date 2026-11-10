# SecureCloudOps — tổng kết 10 Phase

Tài liệu này tóm tắt tiến trình dự án và phân biệt rõ phần đã triển khai với phần chỉ mới thiết kế/kiểm thử mô phỏng.

| Phase | Phạm vi | Kết quả / trạng thái cần trình bày |
|---|---|---|
| 1 — Local MVP | FastAPI, PostgreSQL, SQLAlchemy, Docker Compose, pytest | Workload local có `/health` và CRUD task; Docker Compose và test được cấu hình. |
| 2 — AWS Networking | VPC `10.0.0.0/16`, hai public + hai private subnets, IGW, route tables, Security Groups | Network foundation được tạo; NAT Gateway không được tạo để giảm chi phí. |
| 3 — Infrastructure as Code | Terraform + AWS provider | Terraform `validate` từng pass và một lần `plan` báo `No changes` ở trạng thái đã kiểm tra. Không commit Terraform state. |
| 4 — API/workload verification | Kiểm tra OpenAPI/Swagger, health và task endpoints | API routes được kiểm tra qua `/docs`; các thao tác CRUD có test cơ bản. Không mô tả phần chưa có test là đã được kiểm thử đầy đủ. |
| 5 — AWS workload | EC2 chạy API + PostgreSQL bằng Docker Compose | `/health` trên EC2 từng trả HTTP 200 và database container từng healthy; EC2 hiện ở trạng thái stopped. Đây là EC2, không phải ECS/RDS. |
| 6 — Identity and secrets | EC2 IAM role, Parameter Store `SecureString`, KMS | Workload lấy database password bằng IAM role; secret không nằm trong source hoặc Compose YAML. Một số thao tác vượt quyền được kiểm tra bằng AccessDenied. |
| 7 — CI/CD | GitHub Actions, pytest, Docker build, AWS OIDC, SSM deployment | CI/build workflow tồn tại; OIDC và SSM deploy được cấu hình. Job deploy có điều kiện qua `ENABLE_EC2_DEPLOY`; cần dẫn chứng từ Actions run gần nhất. |
| 8 — Edge and audit | CloudFront, WAF, CloudTrail, CloudWatch | Origin verification: request không có token trả HTTP 403, có token trả HTTP 200. Không tuyên bố WAF đã chống được mọi tấn công. |
| 9 — Threat detection | GuardDuty, Security Hub, Inspector | GuardDuty sample findings đã được tạo để kiểm tra. Inspector account/coverage được bật ở các loại resource đã cấu hình; cần theo dõi phí và coverage. |
| 10 — Event-driven response | EventBridge + Lambda + quarantine Security Group | Pattern positive/negative pass; Lambda direct test pass trong DRY_RUN; GuardDuty TorRelay sample đến Lambda và bị skip. Chưa chạy live quarantine. |

## Trạng thái demo an toàn đã xác nhận sau Phase 10

- Lambda `Active`, `DRY_RUN=true`.
- EventBridge production rule `DISABLED`, production pattern đã được khôi phục.
- EventBridge có một Lambda target.
- EC2 `stopped`, vẫn gắn Security Group gốc.
- Không còn tag `SecureCloudOpsAutoRemediate` hoặc rollback backup tag.
- Quarantine Security Group tồn tại, đúng VPC và không có inbound/outbound rules.

## Không được tuyên bố quá mức

- Chưa thực hiện live remediation thay Security Group của EC2.
- Chưa triển khai ECS + RDS trong workload đã xác nhận; workload AWS đang được mô tả là EC2 + Docker Compose.
- CI/CD không đồng nghĩa mỗi push đều deploy thành công; job deploy có điều kiện.
- EC2 stopped không đồng nghĩa toàn bộ AWS resource không còn chi phí.
- Đây là portfolio lab, không phải production system có HA/DR hoặc đã chứng nhận compliance.
