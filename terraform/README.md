# TF1 Triage Hub - AWS Terraform

Terraform trong folder này dựng **Milestone 1 infrastructure baseline** cho CDO-05.

Flow infra hỗ trợ:

```text
Alertmanager
-> Ingest Lambda
-> SQS FIFO Incident Queue + FIFO DLQ
-> CDO Correlator Worker on EKS
-> DynamoDB incident_state
-> S3 audit/evidence
-> AI Engine on EKS
-> Slack/Jira payload hoặc integration layer
```

Terraform chưa deploy Kubernetes workload như Demo App, Prometheus, Loki, Grafana, CDO Correlator Worker hoặc AI Engine. Các phần đó thuộc workload/deployment layer sau khi AWS infra base đã sẵn sàng.

## Project Layout

```text
terraform/
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
├── modules/
│   ├── network/
│   ├── security-groups/
│   ├── security/
│   ├── eks/
│   ├── iam-irsa/
│   ├── storage/
│   ├── queue/
│   ├── ingest-lambda/
│   ├── ecr/
│   ├── monitoring/
│   └── optional-controls/
├── lambda/
│   └── ingest/
└── docs/
```

Mỗi environment là một Terraform root riêng. Chạy Terraform trong `environments/<env>`, không chạy ở root `terraform/`.

## Environments

| Environment | Mục đích | Ghi chú |
|---|---|---|
| `dev` | Demo/capstone apply nhanh | Giữ cost thấp, public EKS endpoint đang mở theo default dev. |
| `staging` | Kiểm thử gần prod | Dùng CIDR allowlist cho EKS public endpoint. |
| `prod` | Production-like template | Bật NAT, WAF, CloudTrail, S3 Object Lock trong `terraform.tfvars.example`. |

## Current Dev Defaults

```hcl
aws_region              = "us-east-1"
node_instance_types     = ["m7i-flex.large"]
node_ami_type           = "AL2023_x86_64_STANDARD"
node_desired_size       = 2
enable_ebs_csi_addon    = true
enable_nat_gateway      = false
enable_vpc_endpoints    = true
lambda_reserved_concurrency = -1
```

Lý do chọn `m7i-flex.large`: x86_64, 2 vCPU, 8 GiB RAM, phù hợp hơn `t3.micro` cho EKS add-ons + AI Engine + worker + observability demo. Không dùng `t4g` nếu chưa xác nhận AI image có ARM64 manifest.

## Cách Chạy Dev

```powershell
cd D:\XBrain\Projects\xbrain-learners\capstone-phase2\temp\aiops\terraform\environments\dev
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -recursive
terraform validate
terraform plan -input=false
terraform apply -auto-approve -input=false
```

Kiểm tra sau apply:

```powershell
terraform plan -input=false
aws eks update-kubeconfig --region us-east-1 --name tf1-triage-hub-dev
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
aws eks list-addons --region us-east-1 --cluster-name tf1-triage-hub-dev
```

Destroy sau khi test/demo để tránh cost:

```powershell
terraform destroy -auto-approve -input=false
terraform state list
```

## Validation

Sau khi module hóa, đã chạy:

```text
terraform fmt -recursive
terraform init -input=false -lockfile=readonly
terraform validate
terraform plan -input=false -no-color
```

Kết quả `dev`:

```text
terraform validate: Success
terraform plan: 117 to add, 0 to change, 0 to destroy
aws_region output: us-east-1
eks_cluster_name output: tf1-triage-hub-dev
```

## Notes Quan Trọng

- Resource logic được refactor từ bộ Terraform đã từng apply thành công, không viết lại design mới.
- Module hóa làm đổi Terraform resource address, ví dụ `aws_vpc.this` thành `module.network.aws_vpc.this`.
- Nếu đã có state thật từ layout cũ, cần migration bằng `moved` block hoặc `terraform state mv`.
- Nếu repo/team chưa apply layout cũ, có thể dùng module layout này như fresh infrastructure.
- SQS chỉ giữ alert event, không giữ raw metrics/logs.
- DynamoDB giữ workflow state/idempotency/ticket pointer.
- S3 giữ bounded evidence/audit artifacts.
- AI Engine không public internet; chỉ nên gọi nội bộ từ CDO Worker.

## AI Image Note

AIO-01 image hiện ở ECR `us-east-1`:

```text
589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0
```

Terraform mặc định dựng EKS private nodes ở `us-east-1`, cùng region với AIO ECR image. Vì vậy workload AI Engine có thể dùng image handoff trực tiếp nếu cross-account pull permission vẫn còn hiệu lực.
