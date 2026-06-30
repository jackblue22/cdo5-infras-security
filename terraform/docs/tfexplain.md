# TF1 Triage Hub Terraform Explain

## Current Layout Update

Terraform hiện dùng layout `modules/` + `environments/`:

```text
terraform/
├── environments/dev
├── environments/staging
├── environments/prod
└── modules/*
```

Chạy Terraform trong từng environment, ví dụ:

```powershell
cd D:\XBrain\Projects\xbrain-learners\capstone-phase2\temp\aiops\terraform\environments\dev
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan -input=false
```

Validation sau khi module hóa:

```text
terraform validate: Success
terraform plan: 117 to add, 0 to change, 0 to destroy
```

Ghi chú: trước khi module hóa, cùng resource logic này đã từng apply thật thành công, verify EKS/node/add-ons healthy, rồi destroy sạch để tránh cost.

File này giải thích Terraform trong folder này đang tạo gì, vì sao các rule infra/security khớp với thiết kế CDO-05, và kết quả apply thật trên AWS.

## 1. Scope

Đây là Milestone 1: **AWS infrastructure + security baseline**.

Terraform hiện tạo:

- VPC, public/private subnets, route tables.
- EKS cluster làm compute platform chính.
- EKS managed node group cho workload layer.
- EKS add-ons lõi: `vpc-cni`, `kube-proxy`, `coredns`, optional `aws-ebs-csi-driver`.
- Lambda ingest để nhận alert webhook và đẩy vào SQS FIFO.
- SQS FIFO incident queue + FIFO DLQ.
- DynamoDB `incident_state`.
- S3 audit/evidence bucket.
- IAM roles, IAM policies, IRSA roles.
- Secrets Manager placeholder secrets.
- KMS key cho tài nguyên nhạy cảm.
- CloudWatch log groups, alarms, dashboard.
- Security groups cho ALB/app/worker/AI/observability/integration/VPC endpoints.
- VPC endpoints để private workloads gọi AWS APIs.

Terraform chưa deploy Kubernetes workload như Demo App, CDO Correlator Worker, AI Engine, Prometheus, Loki, Grafana, NetworkPolicy, Helm hoặc GitOps. Các phần đó là workload/deployment layer sau Milestone 1.

## 2. Runtime Flow Được Hỗ Trợ

```text
Alertmanager
-> Ingest Lambda
-> SQS FIFO Incident Queue
-> CDO Correlator Worker on EKS
-> DynamoDB incident_state
-> S3 audit/evidence
-> AI Engine on EKS
-> Integration Layer / Jira / Slack
```

Điểm chốt:

- SQS FIFO chỉ giữ alert event, không giữ raw metrics/logs.
- Raw telemetry vẫn nằm ở Prometheus/Loki/CloudWatch.
- DynamoDB giữ workflow state, idempotency key, ticket/thread pointer.
- S3 giữ artifact/audit/evidence như alert payload, AI request/response, RCA report.
- AI Engine không public internet; chỉ nên được gọi nội bộ từ CDO Worker hoặc approved internal caller.

## 3. Resource Order

Terraform tự tính dependency graph, nhưng logic triển khai là:

1. Provider/data sources: account, region, AZs.
2. KMS + Secrets Manager placeholders.
3. VPC, subnets, route tables, optional NAT.
4. VPC endpoints: SQS, ECR API/DKR, EC2, STS, Secrets Manager, KMS, CloudWatch Logs, S3, DynamoDB.
5. Security groups and rules.
6. EKS cluster.
7. Pre-node EKS add-ons: `vpc-cni`, `kube-proxy`.
8. EKS managed node group.
9. Post-node EKS add-ons: `coredns`, optional `aws-ebs-csi-driver`.
10. SQS FIFO + FIFO DLQ.
11. DynamoDB incident state.
12. S3 audit/evidence bucket.
13. Lambda ingest + Function URL.
14. IRSA roles for Correlator Worker, AI Engine, EBS CSI, AWS Load Balancer Controller.
15. CloudWatch alarms/dashboard.

## 4. Security Rules

### IAM / IRSA

Không có role chung cho tất cả workloads.

- `ingest-lambda-role`: chỉ write logs, đọc webhook signing secret, gửi message vào SQS FIFO.
- `correlator-worker-irsa`: consume SQS FIFO, thao tác DynamoDB state, đọc/ghi S3 evidence, đọc runtime secrets cần thiết.
- `ai-engine-irsa`: đọc bounded evidence, đọc service auth secret, optional Bedrock invoke nếu bật.
- `ebs-csi-driver-irsa`: cấp quyền `AmazonEBSCSIDriverPolicy` cho `kube-system/ebs-csi-controller-sa`.
- `aws-load-balancer-controller-irsa`: dùng cho ALB ingress ở workload layer.

DLQ replay mặc định không bật. Nếu cần tool replay thủ công:

```hcl
enable_worker_dlq_replay_permissions = true
```

### SQS FIFO

Queue chính:

- `tf1-triage-hub-dev-incident-queue.fifo`
- SSE enabled.
- TLS-only queue policy.
- Redrive sang FIFO DLQ sau `max_receive_count`.
- Lambda ingest gửi `MessageGroupId` theo hash `tenant_id#service#env`.
- Lambda ingest gửi `MessageDeduplicationId` theo hash tenant/service/env/fingerprint/status/start time.

Lý do: giữ thứ tự theo tenant/service/env và giảm duplicate side effect.

### Network / Security Groups

Baseline security groups:

- `public_alb`: public HTTPS entrypoint.
- `app_workload`: app target sau ALB.
- `aiops_worker`: CDO Correlator Worker boundary.
- `ai_engine`: internal AI Engine API boundary.
- `integration`: Jira/Slack integration boundary.
- `observability`: Prometheus/Loki/Grafana/OTel boundary.
- `vpc_endpoints`: private AWS API endpoint boundary.

Các rule chính:

```text
internet/admin CIDR -> public_alb:443
public_alb -> app_workload:8080
app_workload -> observability:4317/4318
aiops_worker -> ai_engine:8080
workloads -> vpc_endpoints:443
deny public -> ai-engine/prometheus/loki/grafana/worker
```

Tenant isolation không chỉ dựa vào SG. Nó cần kết hợp `tenant_id`, DynamoDB key, S3 prefix, IAM condition, bounded query và Kubernetes NetworkPolicy ở workload layer.

### VPC Endpoints

Private workloads dùng VPC endpoints thay vì NAT cho AWS APIs:

- SQS
- ECR API
- ECR DKR
- EC2
- STS
- Secrets Manager
- KMS
- CloudWatch Logs
- S3 gateway endpoint
- DynamoDB gateway endpoint

EC2 endpoint được thêm vì EKS private nodes và VPC CNI cần gọi EC2 API ổn định khi không bật NAT Gateway.

### S3 Audit / Evidence

Audit bucket có:

- Block Public Access.
- Versioning.
- SSE-KMS khi `enable_kms = true`.
- Bucket policy deny non-TLS.
- Lifecycle theo `audit_retention_days`.
- Optional Object Lock nếu bật trước khi tạo bucket.

Object Lock đang tắt mặc định cho dev vì đây là quyết định immutable bucket cần chốt trước. Prod có thể bật:

```hcl
enable_s3_object_lock         = true
s3_object_lock_retention_days = 90
```

### Lambda Ingest

Function URL đang dùng `AWS_IAM` auth. Prod guardrail không cho dùng `NONE`.

Reserved concurrency default là `-1`, nghĩa là không reserve riêng trong dev account bị giới hạn concurrency. Prod có thể set số dương, ví dụ:

```hcl
lambda_reserved_concurrency = 10
```

## 5. Cost-Aware Defaults

Defaults hiện tại ưu tiên chạy được trong capstone/dev account:

- `enable_nat_gateway = false` để tránh NAT hourly cost.
- VPC endpoints được bật cho AWS APIs cần thiết.
- Node group recommended hiện tại dùng `2 x m7i-flex.large` nếu AWS Free Tier/credit plan của account cho phép. Lý do: x86_64, 2 vCPU/node, 8 GiB RAM/node, đủ khỏe hơn cho EKS add-ons, AI Engine, worker và observability demo.
- Node group dùng `node_ami_type = "AL2023_x86_64_STANDARD"`, tức EKS optimized Amazon Linux 2023 x86_64 managed AMI. Terraform không hard-code AMI ID để AWS tự resolve bản vá mới nhất theo region/Kubernetes version.
- `enable_ebs_csi_addon = true` với node `m7i-flex.large`; chỉ tắt khi fallback về `t3.micro` để validate infra rẻ nhất.
- `enable_waf = false`; bật khi có ALB public thật.
- `enable_cloudtrail = false`; bật nếu chưa có account-level CloudTrail.
- `enable_ai_bedrock_policy = false`; bật khi AI Engine thật sự gọi Bedrock.
- `log_retention_days = 14`.
- `audit_retention_days = 90`.

Production recommendation:

- Dùng node lớn hơn như `t3.medium`, `m6i.large` hoặc node group tách theo workload.
- Với EKS managed node group, ưu tiên `AL2023_x86_64_STANDARD` thay vì custom AMI ID. Chỉ dùng custom launch template/AMI khi có yêu cầu hardening rất cụ thể.
- Bật EBS CSI nếu dùng PVC thật.
- Giới hạn EKS public endpoint CIDR hoặc dùng private endpoint.
- Bật WAF cho public ALB.
- Cân nhắc CloudTrail/Security Hub/GuardDuty theo budget.

AMI/instance check đã verify ở `us-east-1`:

```text
Available candidate instances:
- t3.micro: x86_64, 2 vCPU, 1 GiB RAM.
- t3.small: x86_64, 2 vCPU, 2 GiB RAM.
- t4g.micro: arm64, 2 vCPU, 1 GiB RAM.
- t4g.small: arm64, 2 vCPU, 2 GiB RAM.
- c7i-flex.large: x86_64, 2 vCPU, 4 GiB RAM.
- m7i-flex.large: x86_64, 2 vCPU, 8 GiB RAM.
EKS 1.30 AL2023 x86_64 recommended AMI tại thời điểm check: ami-074234a53fdeeb66a.
```

Không nên pin trực tiếp các AMI ID trên vào Terraform trừ khi demo yêu cầu snapshot cố định, vì AMI recommended có thể thay đổi theo security patch.

Recommendation:

- Chọn `m7i-flex.large` cho demo EKS + AI Engine vì nhiều RAM hơn `c7i-flex.large`.
- Chỉ chọn `c7i-flex.large` nếu workload thiên CPU và không chạy observability stack nặng.
- Không chọn `t4g.micro/t4g.small` cho AI Engine hiện tại nếu chưa xác nhận image AIO có ARM64 manifest.
- Fallback rẻ nhất để test infra-only là `t3.micro`, nhưng không đủ khỏe để demo workload thật thoải mái.

## 6. AI Engine Handoff Note

AIO-01 đã bàn giao AI Engine image cho EKS deployment.

```text
Image URI:
589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0

Pinned digest:
589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine@sha256:ed9d9ca831aa70865e175a611359610c66be5cb56fd33b0487ac687fc4b14f70

Container:
containerPort: 8080
GET /healthz
GET /readyz
GET /metrics
POST /v1/triage
```

CDO account được cấp cross-account pull permission trên AIO ECR repo. Khi viết Kubernetes manifest, nên dùng pinned digest cho prod-like deployment. Tag `v1.0.0` có thể dùng cho demo nhanh.

Lưu ý quan trọng cho bước deploy workload: Terraform hiện mặc định tạo EKS private nodes ở region `us-east-1`, cùng region với image AIO trong ECR `us-east-1`. Vì vậy default path không còn vấn đề cross-region ECR; private nodes có thể pull image qua ECR/VPC endpoints nếu cross-account pull permission vẫn còn hiệu lực.

Nếu sau này team đổi runtime sang region khác `us-east-1`, xử lý theo thứ tự:

1. Replicate/copy image AIO vào ECR của CDO account cùng region với EKS, rồi dùng image URI regional đó trong manifest. Đây là hướng tốt nhất cho cost và security.
2. Bật `enable_nat_gateway = true` để private nodes có egress ra ECR public endpoint. Cách này chạy được nhưng tốn NAT cost và mở egress rộng hơn.
3. Giữ toàn bộ runtime ở `us-east-1` nếu team thống nhất chạy cùng region với AIO/Bedrock.

Pull test:

```powershell
aws ecr get-login-password --region us-east-1 |
  docker login --username AWS --password-stdin 589077667575.dkr.ecr.us-east-1.amazonaws.com

docker pull 589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0
```

Source:

- Release source: `https://github.com/c0mmie-b0msh3ll/xBrain-capstone2/tree/v1.0.0`
- Handoff doc: `https://github.com/c0mmie-b0msh3ll/xBrain-capstone2/blob/v1.0.0/capstone/tf-1/ai/docs/11_v1_0_0_handoff.md`
- Smoke sample: `https://github.com/c0mmie-b0msh3ll/xBrain-capstone2/blob/v1.0.0/capstone/tf-1/ai/engine-skeleton/samples/latency-degradation.request.json`

## 7. Validation Đã Chạy

Các lệnh đã chạy thành công:

```powershell
terraform fmt -recursive
terraform validate
terraform apply -auto-approve -input=false
terraform plan -input=false
aws eks describe-nodegroup --region us-east-1 --cluster-name tf1-triage-hub-dev --nodegroup-name tf1-triage-hub-dev-core
aws eks describe-addon --region us-east-1 --cluster-name tf1-triage-hub-dev --addon-name coredns
aws eks update-kubeconfig --region us-east-1 --name tf1-triage-hub-dev
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
```

Kết quả chính:

```text
terraform validate: Success
terraform apply from empty state: Apply complete, one-shot, no manual mid-run fix
terraform plan: No changes
EKS node group: ACTIVE
Node group size: desired=2, min=1, max=2
Node type: m7i-flex.large
AMI type: AL2023_x86_64_STANDARD
EKS add-ons: vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver
CoreDNS status: ACTIVE
EBS CSI status: ACTIVE after adding dedicated IRSA role
kubectl nodes: 2 Ready
kube-system pods: aws-node, kube-proxy, coredns, ebs-csi-controller, ebs-csi-node Running
```

Config `m7i-flex.large` đã được apply thật và verify bằng `terraform plan` no changes + `kubectl get nodes/pods`.

Sau khi lấy đủ bằng chứng, stack đã được destroy để tránh phát sinh chi phí:

```text
terraform destroy: Destroy complete, 117 resources destroyed
terraform state list: empty
aws eks describe-cluster tf1-triage-hub-dev: ResourceNotFoundException
aws ec2 describe-instances tag:eks:cluster-name=tf1-triage-hub-dev: no running/stopped node instances
```

Lỗi đã gặp và cách sửa:

| Lỗi | Nguyên nhân | Fix |
|---|---|---|
| EKS cluster/log group already exists | Apply trước đó bị ngắt, resource đã tồn tại ngoài state; đồng thời có duplicate log group definition | Import EKS cluster vào state; bỏ `/aws/eks/.../cluster` khỏi `common_log_groups`. |
| EKS replacement do `bootstrap_self_managed_addons` | Imported cluster có value khác default provider | Pin `bootstrap_self_managed_addons = false`. |
| SQS SSE conflict | Không thể bật cùng lúc SSE-SQS managed và KMS CMK | Conditional: dùng KMS khi `enable_kms=true`, ngược lại dùng SSE-SQS. |
| CloudWatch Logs không dùng được KMS key | KMS policy thiếu CloudWatch Logs service principal | Thêm quyền cho `logs.<region>.amazonaws.com`. |
| Node group `t3.medium` fail | Account lúc đó bị giới hạn instance type | Ban đầu fallback sang `t3.micro`; sau khi xác nhận account/free-plan có `m7i-flex.large`, default demo đổi sang `m7i-flex.large`. |
| Lambda reserved concurrency fail | Account concurrency quota thấp | Default `lambda_reserved_concurrency = -1`. |
| Node group stuck NotReady | `bootstrap_self_managed_addons = false` nhưng Terraform tạo all add-ons sau node group, làm node thiếu CNI | Tách `vpc-cni` và `kube-proxy` thành pre-node add-ons; `coredns` và EBS CSI là post-node add-ons. |
| EBS CSI timeout / CrashLoopBackOff | EBS CSI controller thiếu AWS credential, cố dùng IMDS và fail | Tạo `ebs-csi-driver-irsa` và truyền `service_account_role_arn` vào managed add-on. |

## 8. Cách Chạy

```powershell
cd D:\XBrain\Projects\xbrain-learners\capstone-phase2\temp\aiops\terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan -input=false
terraform apply -auto-approve -input=false
```

Kiểm tra sau apply:

```powershell
terraform output
terraform plan -input=false
aws eks update-kubeconfig --region us-east-1 --name tf1-triage-hub-dev
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
```

Destroy sau demo/test:

```powershell
terraform destroy -auto-approve -input=false
```

## 9. Việc Còn Lại Sau Milestone 1

Workload layer cần làm tiếp:

- Kubernetes namespaces: `app`, `aiops`, `ai-engine`, `observability`.
- ServiceAccount annotations gắn IRSA role ARN.
- AWS Load Balancer Controller Helm install.
- Demo App deployment/service/ingress.
- CDO Correlator Worker deployment.
- AI Engine deployment dùng image AIO-01 đã bàn giao.
- Prometheus/Loki/Grafana/OTel deployment.
- Kubernetes NetworkPolicy, ResourceQuota, LimitRange, Pod Security labels.
- CI/CD hoặc GitOps pipeline.

Milestone 1 đã chốt được phần base AWS infra chạy thật, security boundary rõ, và output đủ để workload layer gắn vào.
