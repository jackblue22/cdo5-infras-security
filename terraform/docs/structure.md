# Terraform Structure

Folder này dùng layout **modules + environments**.

## Root

```text
terraform/
├── environments/
├── modules/
├── lambda/
└── docs/
```

Không chạy Terraform ở root `terraform/`. Hãy chạy trong từng environment:

```powershell
cd environments\dev
terraform init
terraform plan
```

## Environments

```text
environments/
├── sandbox/
├── dev/
├── staging/
└── prod/
```

Mỗi environment có:

```text
main.tf
variables.tf
outputs.tf
providers.tf
versions.tf
locals.tf
data.tf
terraform.tfvars.example
```

Khác biệt chính nằm ở `environment` default và `terraform.tfvars.example`.

`sandbox` được thêm để tương thích với layout tham khảo trong `temp/aiops/infra/environments/sandbox`. Logic bên trong vẫn copy từ `dev`, tức là dùng bộ Terraform đã từng apply thành công.

## Modules

| Module | Trách nhiệm |
|---|---|
| `network` | VPC, public/private subnets, route tables, NAT, VPC endpoints |
| `networking` | Compatibility alias của `network` để match layout `infra` cho `sandbox` |
| `security-groups` | SG boundary cho ALB, app, worker, AI, integration, observability |
| `security` | KMS key và Secrets Manager placeholder |
| `eks` | EKS cluster, managed node group, EKS add-ons, EBS CSI IRSA |
| `eks-addons` | Placeholder cho Helm/GitOps add-ons sau Milestone 1 |
| `iam-irsa` | IRSA cho CDO Worker, AI Engine, AWS Load Balancer Controller |
| `storage` | S3 audit/evidence bucket và DynamoDB incident state |
| `queue` | SQS FIFO incident queue và FIFO DLQ |
| `ingest-lambda` | Alert ingest Lambda, IAM role, log group, Function URL |
| `incident-ingest` | Compatibility alias của `ingest-lambda` để match layout `infra` cho `sandbox` |
| `ecr` | ECR repositories cho workload images tương lai |
| `external-secrets` | Placeholder cho External Secrets/CSI bootstrap sau Milestone 1 |
| `github-oidc` | Placeholder cho CI/CD OIDC role sau Milestone 1 |
| `monitoring` | CloudWatch log groups, alarms, SNS topic, dashboard |
| `optional-controls` | Optional WAF và CloudTrail |

## Mapping Với Folder `infra`

Folder `temp/aiops/infra` là reference về organization/path, không phải source code chính để deploy. Mapping hiện tại:

| `infra` reference | `terraform` runtime source | Ghi chú |
|---|---|---|
| `environments/sandbox` | `environments/sandbox` | Đã thêm để CI/CD dễ trỏ đúng path. |
| `modules/networking` | `modules/networking` alias từ `modules/network` | Terraform runtime module tự quản lý VPC/subnet/route/VPC endpoints. |
| `modules/eks` | `modules/eks` | Runtime module có EKS, node group, add-ons và OIDC provider. |
| `modules/eks-addons` | `modules/eks` + future workload bootstrap | EKS managed add-ons đang nằm trong `modules/eks`; Helm add-ons như ArgoCD/Prometheus chưa thuộc Milestone 1. |
| `modules/incident-ingest` | `modules/incident-ingest` alias từ `modules/ingest-lambda` + root modules `queue/storage/security` | Runtime flow đầy đủ hơn: Lambda ingest, SQS FIFO/DLQ, DynamoDB state, S3 audit, Secrets/KMS. |
| `modules/ecr` | `modules/ecr` | Tạo repo ECR cho workload sau này. |
| `modules/github-oidc` | Chưa triển khai trong Milestone 1 | CI/CD OIDC là phase sau, không chặn infra baseline. |
| `modules/external-secrets` | Chưa triển khai trong Milestone 1 | Secret containers đã ở AWS Secrets Manager; sync vào Kubernetes thuộc cluster bootstrap phase. |

## State Migration Note

Module hóa đổi resource address:

```text
aws_vpc.this
-> module.network.aws_vpc.this
```

Nếu đã có Terraform state thật từ layout cũ, cần migration bằng `moved` block hoặc `terraform state mv`.

Nếu stack đã destroy sạch hoặc repo mới chưa apply, có thể dùng layout này như fresh deployment.
