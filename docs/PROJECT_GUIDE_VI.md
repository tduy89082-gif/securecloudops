# Hướng dẫn chốt dự án SecureCloudOps

## 1. Sản phẩm của dự án là gì?

SecureCloudOps là một môi trường cloud lab có một workload API thật và một lớp bảo mật/giám sát đi kèm. API FastAPI sử dụng PostgreSQL, được đóng gói bằng Docker Compose. Terraform mô tả mạng AWS. EC2 chạy workload; IAM role và Systems Manager Parameter Store giúp workload lấy secret mà không phải nhúng mật khẩu vào source code. CloudFront/WAF bảo vệ lớp truy cập; CloudTrail/CloudWatch và các dịch vụ GuardDuty, Security Hub, Inspector hỗ trợ giám sát. Khi GuardDuty phát hiện finding phù hợp, EventBridge có thể gọi Lambda để kiểm tra điều kiện cách ly EC2.

Điểm quan trọng: đây là dự án học tập/portfolio. Không nên mô tả nó là một hệ thống production có HA hoặc đã tự động cách ly máy thật, vì phần remediation mới được kiểm thử an toàn ở chế độ DRY_RUN.

## 2. Tại sao từng lớp cần thiết?

- **Application:** tạo workload cụ thể để có thứ cần triển khai và bảo vệ; nếu chỉ dựng VPC/security service thì khó chứng minh kỹ năng vận hành ứng dụng.
- **Docker:** đóng gói API và database để môi trường chạy nhất quán hơn giữa máy cá nhân và EC2.
- **Terraform:** lưu cấu hình hạ tầng dưới dạng code, có thể review, tái tạo và phát hiện drift qua plan.
- **VPC/Subnets/Routes/Security Groups:** kiểm soát địa chỉ mạng, đường đi và luồng kết nối vào workload.
- **IAM role:** cấp quyền cho EC2/Lambda theo danh tính workload, tránh đặt access key dài hạn trên máy chủ.
- **KMS + Parameter Store SecureString:** mã hóa và quản lý secret tập trung; ứng dụng lấy secret khi chạy.
- **CloudFront + WAF + origin verification:** đưa lớp edge vào trước origin và kiểm tra request đến origin có bằng chứng xác thực hay không. Đây không thay thế việc khóa inbound trực tiếp ở Security Group.
- **CloudTrail/CloudWatch:** phục vụ điều tra hoạt động và quan sát log.
- **GuardDuty/Security Hub/Inspector:** giúp phát hiện và tổng hợp các vấn đề bảo mật khác nhau; mỗi dịch vụ có phạm vi và mô hình tính phí riêng.
- **EventBridge + Lambda:** biến finding thành một workflow có thể kiểm tra/ứng phó tự động thay vì chỉ gửi cảnh báo.

## 3. Trạng thái chốt đã xác nhận

- Terraform `validate` thành công; lần `plan` sau đó báo `No changes`.
- `/health` trên EC2 từng trả HTTP 200.
- CloudFront origin verification: thiếu token trả 403; có token trả 200.
- Lambda direct test: sample trả `SKIPPED`; finding tổng hợp hợp lệ trong chế độ dry-run trả `DRY_RUN`.
- GuardDuty sample TorRelay đã đi qua EventBridge và gọi Lambda. CloudWatch ghi `GuardDuty sample finding detected. Skipping remediation.`
- Sau test, EventBridge `DISABLED`, production event pattern đã khôi phục, EC2 `stopped`, Security Group gốc vẫn gắn, opt-in tag không còn.

## 4. Những việc không được hiểu nhầm là đã làm

- Chưa chạy live remediation để thay Security Group của EC2.
- Chưa xác nhận CI tự động deploy EC2 thành công ở mọi lần push; job SSM đã từng bị skip theo điều kiện.
- Không thể nói hệ thống AWS chạy miễn phí hoặc không phát sinh chi phí chỉ vì EC2 đang stopped.
- Không thể nói hệ thống đã đạt production readiness, HA, compliance hoặc disaster recovery.

## 5. Quy trình demo an toàn

1. Xác nhận đúng AWS account và region.
2. Xác nhận EC2, Lambda, EventBridge và Security Group đang ở trạng thái dự kiến.
3. Dùng sample finding để minh họa event flow; không bật live remediation.
4. Mở CloudWatch Logs cho Lambda để chỉ ra dòng sample bị skip.
5. Kết thúc bằng kiểm tra EventBridge disabled, `DRY_RUN=true`, EC2 stopped, SG gốc không đổi.
6. Che toàn bộ secret, account/public IP không cần thiết và thông tin cá nhân trong ảnh chụp.

## 6. Kiểm tra trạng thái AWS cuối cùng

Trong thư mục `scripts/` có `verify-aws-final-state.ps1`. Script chỉ gọi các API đọc (`describe`, `get`, `list`) để kiểm tra account, Lambda `DRY_RUN`, EventBridge disabled/production pattern, target, EC2, tag và quarantine Security Group. Script không bật rule, không gắn tag, không sửa Security Group và không xóa tài nguyên. Chạy từ PowerShell:

```powershell
.\scripts\verify-aws-final-state.ps1
```

## 7. Ưu tiên trước khi đưa GitHub/CV

1. Đưa README và các file trong `docs/` vào repository thật; điều chỉnh đường dẫn theo cây thư mục thực tế.
2. Thêm sơ đồ kiến trúc Mermaid và ảnh bằng chứng đã che thông tin nhạy cảm.
3. Kiểm tra `.gitignore` có `.env`, `*.pem`, Terraform state/backup và file credential.
4. Mở GitHub Actions run gần nhất, ghi rõ job nào pass và job deploy nào skip.
5. Kiểm tra AWS Billing/Cost Explorer và xóa/tắt resource không còn cần thiết theo dependency; không chạy `terraform destroy` một cách mù quáng.
6. Tạo GitHub release/tag cho phiên bản portfolio đã được tài liệu hóa.
