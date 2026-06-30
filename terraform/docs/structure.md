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

## Modules

| Module | Trách nhiệm |
|---|---|
| `network` | VPC, public/private subnets, route tables, NAT, VPC endpoints |
| `security-groups` | SG boundary cho ALB, app, worker, AI, integration, observability |
| `security` | KMS key và Secrets Manager placeholder |
| `eks` | EKS cluster, managed node group, EKS add-ons, EBS CSI IRSA |
| `iam-irsa` | IRSA cho CDO Worker, AI Engine, AWS Load Balancer Controller |
| `storage` | S3 audit/evidence bucket và DynamoDB incident state |
| `queue` | SQS FIFO incident queue và FIFO DLQ |
| `ingest-lambda` | Alert ingest Lambda, IAM role, log group, Function URL |
| `ecr` | ECR repositories cho workload images tương lai |
| `monitoring` | CloudWatch log groups, alarms, SNS topic, dashboard |
| `optional-controls` | Optional WAF và CloudTrail |

## State Migration Note

Module hóa đổi resource address:

```text
aws_vpc.this
-> module.network.aws_vpc.this
```

Nếu đã có Terraform state thật từ layout cũ, cần migration bằng `moved` block hoặc `terraform state mv`.

Nếu stack đã destroy sạch hoặc repo mới chưa apply, có thể dùng layout này như fresh deployment.
