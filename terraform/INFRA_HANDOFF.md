# TF1 Triage Hub - Terraform Infra Handoff

**Team:** CDO-05  
**Environment verified:** `dev`  
**AWS region:** `us-east-1`  
**Last verified:** 2026-06-30  
**Scope:** Milestone 1 - AWS infrastructure baseline + security foundation.

File này là bản handoff ngắn gọn để teammate biết Terraform hiện đã tạo gì, chưa tạo gì, cần chạy lệnh nào, và cần cẩn thận điểm nào.

---

## 1. Kết luận nhanh

Terraform hiện tại **đã apply thành công cho môi trường `dev`**.

Kết quả kiểm tra gần nhất:

```text
terraform apply: success
terraform plan after apply: No changes
EKS cluster: tf1-triage-hub-dev
EKS nodes: 2 nodes Ready
EKS add-ons: vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver
Kubernetes workload layer: chưa deploy app/AI/observability workload
```

Nếu đang dùng đúng local state hiện tại trong:

```text
temp/aiops/terraform/environments/dev
```

thì chạy lại:

```powershell
terraform apply -auto-approve -input=false
```

sẽ gần như chỉ kiểm tra lại và ra `No changes`.

Nếu teammate copy folder sang repo khác hoặc máy khác mà **không dùng chung Terraform state**, không nên assume là apply một cú sẽ an toàn. Khi resource AWS đã tồn tại nhưng state không biết, Terraform có thể báo conflict kiểu `Cluster already exists`.

---

## 2. Cách chạy đúng

Chạy Terraform trong từng environment, không chạy ở root `terraform/`.

```powershell
cd D:\XBrain\Projects\xbrain-learners\capstone-phase2\temp\aiops\terraform\environments\dev
terraform init
terraform fmt -recursive
terraform validate
terraform plan -input=false
terraform apply -auto-approve -input=false
```

Kiểm tra EKS sau apply:

```powershell
aws eks update-kubeconfig --region us-east-1 --name tf1-triage-hub-dev
kubectl get nodes -o wide
kubectl get pods -A -o wide
aws eks list-addons --region us-east-1 --cluster-name tf1-triage-hub-dev
```

Destroy khi không test/demo nữa để tránh cost:

```powershell
terraform destroy -auto-approve -input=false
```

---

## 3. Infra đã tạo

### 3.1 Network

Module: `modules/network`

Đã tạo:

- VPC: `vpc-068bb3e8b800af818`
- Public subnets cho public ALB sau này.
- Private subnets cho EKS worker nodes.
- Internet Gateway.
- Route tables.
- VPC endpoints:
  - S3
  - DynamoDB
  - SQS
  - ECR API
  - ECR Docker
  - CloudWatch Logs
  - Secrets Manager
  - STS
  - EC2
  - KMS
- Security group riêng cho VPC endpoints.

Mục đích:

```text
Giữ EKS nodes trong private subnet và cho workload gọi AWS APIs qua private endpoints thay vì public internet khi có thể.
```

### 3.2 Security Groups

Module: `modules/security-groups`

Đã tạo baseline SG:

| SG | Mục đích |
|---|---|
| `public_alb` | Public HTTPS entrypoint cho app/demo API sau này. |
| `app_workload` | App target sau ALB. |
| `aiops_worker` | Boundary cho CDO Correlator Worker. |
| `ai_engine` | Boundary cho AI Engine API nội bộ. |
| `integration` | Boundary cho Jira/Slack integration. |
| `observability` | Boundary cho Prometheus/Loki/Grafana/OTel. |
| `vpc_endpoints` | Boundary cho private AWS API endpoints. |

Output hiện tại:

```text
public_alb:    sg-0218415dc268dfa69
app_workload:  sg-05045f6ceaeb37f1a
aiops_worker:  sg-03b4ec01372432b10
ai_engine:     sg-062de8794f9f79f0d
integration:   sg-0bd73754089acbc58
observability: sg-08a14e76cbfddaf24
vpc_endpoints: sg-0be7e62ebea5afaa0
```

Quan trọng:

- Public traffic chỉ nên đi vào `public_alb`.
- AI Engine không public internet.
- Worker gọi AI Engine nội bộ.
- App gửi telemetry sang observability.
- Các workload gọi AWS APIs qua VPC endpoint SG.

### 3.3 EKS

Module: `modules/eks`

Đã tạo:

- EKS cluster: `tf1-triage-hub-dev`
- Kubernetes version: `1.30`
- Node group: `tf1-triage-hub-dev-core`
- Node instance type: `m7i-flex.large`
- Node AMI: `AL2023_x86_64_STANDARD`
- Desired nodes: `2`
- Cluster log group.
- EKS managed add-ons:
  - `vpc-cni`
  - `kube-proxy`
  - `coredns`
  - `aws-ebs-csi-driver`
- OIDC provider cho IRSA.
- EBS CSI Driver IRSA.

Đã verify:

```text
2 EKS nodes Ready
kube-system pods Running
```

### 3.4 IAM / IRSA

Module: `modules/iam-irsa`

Đã tạo IRSA roles:

| Role | Dùng cho |
|---|---|
| `tf1-triage-hub-dev-correlator-worker-irsa` | CDO Correlator Worker trong namespace `aiops`. |
| `tf1-triage-hub-dev-ai-engine-irsa` | AI Engine trong namespace `ai-engine`. |
| `tf1-triage-hub-dev-aws-lbc-irsa` | AWS Load Balancer Controller trong `kube-system`. |
| `tf1-triage-hub-dev-ebs-csi-driver-irsa` | EBS CSI controller trong `kube-system`. |

Output quan trọng:

```text
correlator_worker_role_arn = arn:aws:iam::056755224027:role/tf1-triage-hub-dev-correlator-worker-irsa
ai_engine_role_arn         = arn:aws:iam::056755224027:role/tf1-triage-hub-dev-ai-engine-irsa
aws_lbc_role_arn           = arn:aws:iam::056755224027:role/tf1-triage-hub-dev-aws-lbc-irsa
```

Lưu ý về AWS Load Balancer Controller:

```text
Terraform đã tạo IAM role/policy cho AWS Load Balancer Controller.
Terraform chưa install controller bằng Helm.
```

Khi teammate cài controller bằng Helm/GitOps, service account phải là:

```text
namespace: kube-system
serviceAccount: aws-load-balancer-controller
annotation: eks.amazonaws.com/role-arn = arn:aws:iam::056755224027:role/tf1-triage-hub-dev-aws-lbc-irsa
```

### 3.5 Queue

Module: `modules/queue`

Đã tạo:

- SQS FIFO incident queue:

```text
https://sqs.us-east-1.amazonaws.com/056755224027/tf1-triage-hub-dev-incident-queue.fifo
```

- SQS FIFO DLQ:

```text
https://sqs.us-east-1.amazonaws.com/056755224027/tf1-triage-hub-dev-incident-dlq.fifo
```

Mục đích:

```text
SQS chỉ giữ alert event đã normalize, không giữ raw metrics/logs.
```

### 3.6 Storage

Module: `modules/storage`

Đã tạo:

- DynamoDB incident state table:

```text
tf1-triage-hub-dev-incident-state
```

- S3 audit/evidence bucket:

```text
tf1-triage-hub-dev-audit-20260630033629284900000001
```

Mục đích:

- DynamoDB giữ workflow state, idempotency key, retry count, Jira/Slack pointer.
- S3 giữ alert payload, evidence bundle, AI request/response, audit artifacts.

### 3.7 Secrets / KMS

Module: `modules/security`

Đã tạo:

- KMS key + alias cho encryption.
- Secrets Manager secrets cho:
  - `webhook_signing_key`
  - `service_auth_token`
  - `jira_api_token`
  - `slack_webhook_url`
  - `grafana_admin_password`

Lưu ý:

```text
Terraform chỉ tạo secret container, không nên commit secret value vào repo.
Secret value thật cần được set/update qua AWS console, AWS CLI, hoặc secret management flow riêng.
```

### 3.8 Ingest Lambda

Module: `modules/ingest-lambda`

Đã tạo:

- Lambda: `tf1-triage-hub-dev-ingest-alert`
- Lambda Function URL:

```text
https://5zfetkgvwdwpxugi5o4ycnfciu0xdpcg.lambda-url.us-east-1.on.aws/
```

Lambda hiện làm:

- Nhận webhook alert.
- Verify HMAC nếu có signing secret.
- Check timestamp chống replay.
- Validate `tenant_id`, `service`, `env`, `severity`, `alert_fingerprint`.
- Check `X-Tenant-Id` match payload.
- Normalize alert.
- Gửi message vào SQS FIFO với `MessageGroupId` và `MessageDeduplicationId`.

Trade-off:

```text
Function URL đủ cho demo/MVP.
API Gateway là production hardening option nếu endpoint public thật và cần throttling/auth/API management mạnh hơn.
```

### 3.9 ECR

Module: `modules/ecr`

Đã tạo ECR repos nội bộ CDO:

```text
056755224027.dkr.ecr.us-east-1.amazonaws.com/tf1-triage-hub-dev/ai-engine
056755224027.dkr.ecr.us-east-1.amazonaws.com/tf1-triage-hub-dev/correlator-worker
056755224027.dkr.ecr.us-east-1.amazonaws.com/tf1-triage-hub-dev/demo-app
056755224027.dkr.ecr.us-east-1.amazonaws.com/tf1-triage-hub-dev/observability-tools
```

AIO-01 AI image handoff hiện tại:

```text
589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0
589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine@sha256:ed9d9ca831aa70865e175a611359610c66be5cb56fd33b0487ac687fc4b14f70
```

CDO account đã được cấp cross-account pull permission theo handoff của AIO-01.

### 3.10 Monitoring trên AWS side

Module: `modules/monitoring`

Đã tạo:

- CloudWatch dashboard: `tf1-triage-hub-dev-pipeline`
- SNS topic: `tf1-triage-hub-dev-alarms`
- CloudWatch alarms cho:
  - Ingest Lambda errors/throttles
  - SQS queue oldest message
  - SQS DLQ visible messages
  - DynamoDB read/write throttles
- CloudWatch log groups cho AWS/pipeline components.

Chưa thay thế Prometheus/Loki/Grafana. CloudWatch ở đây chủ yếu monitor AWS pipeline health.

---

## 4. Chưa có gì

Terraform hiện tại **chưa deploy Kubernetes workload layer**.

Chưa có:

- Namespace `app`
- Namespace `aiops`
- Namespace `ai-engine`
- Namespace `observability`
- AWS Load Balancer Controller Helm release
- ArgoCD
- Prometheus
- Alertmanager
- Loki
- Grafana
- Demo app
- CDO Correlator Worker deployment
- AI Engine deployment
- Jira/Slack integration workload
- Kubernetes Services/Ingress cho app
- PrometheusRule
- ServiceMonitor/PodMonitor
- Kubernetes RBAC cho worker/AI/observability
- Kubernetes NetworkPolicy
- Pod Security labels
- ResourceQuota / LimitRange
- External Secrets Operator hoặc CSI secret sync

Hiện cluster chỉ có EKS system namespace/pods:

```text
default
kube-system
kube-public
kube-node-lease
```

và system pods như:

```text
aws-node
kube-proxy
coredns
ebs-csi-controller
ebs-csi-node
```

---

## 5. Có cần thêm API Gateway không?

Hiện tại **chưa cần thêm API Gateway vào Terraform**.

Recommendation:

```text
App/API chạy trong EKS dùng ALB + AWS Load Balancer Controller.
Alertmanager webhook tạm dùng Lambda Function URL + HMAC.
API Gateway chỉ là prod option cho ingest endpoint nếu cần throttling/auth/API management mạnh hơn.
```

Trade-off:

| Option | Khi dùng | Ghi chú |
|---|---|---|
| Lambda Function URL | Demo/MVP, ít traffic, có HMAC | Đơn giản, ít cost, đang dùng hiện tại. |
| API Gateway -> Lambda | Public webhook production | Throttle/auth/stage/custom domain tốt hơn, nhưng thêm cost và service. |
| ALB + AWS Load Balancer Controller | Public app/API trong EKS | Phù hợp Kubernetes Ingress, đang là lựa chọn chính trong docs `02`. |

---

## 6. Bước tiếp theo nên làm

### Step 1 - Cluster bootstrap

Tạo folder riêng, ví dụ:

```text
cluster-bootstrap/
```

hoặc:

```text
k8s-bootstrap/
```

Nên deploy:

- Namespaces:
  - `app`
  - `aiops`
  - `ai-engine`
  - `observability`
- Pod Security labels.
- RBAC tối thiểu.
- NetworkPolicy default deny + allowlist.
- ServiceAccount có IRSA annotation:
  - `aiops/correlator-worker`
  - `ai-engine/ai-engine-api`
  - `kube-system/aws-load-balancer-controller`
- AWS Load Balancer Controller Helm chart.

### Step 2 - GitOps bootstrap

Cài ArgoCD.

Sau đó để ArgoCD quản lý:

- Prometheus stack
- Loki
- Grafana
- Alertmanager
- Demo app
- CDO Correlator Worker
- AI Engine
- Ingress
- PrometheusRule

### Step 3 - Workload integration

Deploy AI Engine bằng image handoff:

```text
589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0
```

Prod-like nên dùng pinned digest:

```text
589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine@sha256:ed9d9ca831aa70865e175a611359610c66be5cb56fd33b0487ac687fc4b14f70
```

AI Engine container:

```text
containerPort: 8080
GET /healthz
GET /readyz
GET /metrics
POST /v1/triage
```

---

## 7. Lo ngại cần control

### 7.1 Terraform state

Hiện đang dùng local state trong environment folder. Đây là rủi ro lớn nhất nếu nhiều teammate cùng apply.

Production/team recommendation:

```text
Use S3 remote backend + DynamoDB state lock.
```

Nếu không có remote backend:

- Chỉ một người apply/destroy.
- Không copy state lung tung.
- Không xóa local state khi AWS resource còn tồn tại.
- Nếu resource tồn tại ngoài state, phải import hoặc destroy thủ công rồi apply lại.

### 7.2 Cost

Stack đang chạy sẽ tốn cost, đặc biệt:

- EKS control plane.
- 2 EC2 nodes `m7i-flex.large`.
- VPC interface endpoints.
- CloudWatch logs/alarms.
- KMS/Secrets Manager.

Nếu không test tiếp:

```powershell
terraform destroy -auto-approve -input=false
```

### 7.3 Public access

Dev hiện mở một số setting để dễ demo:

- EKS public endpoint dùng default dev.
- Public ALB SG baseline có thể allow rộng cho demo.
- Lambda Function URL tồn tại.

Prod/staging cần tighten:

- EKS public endpoint CIDR allowlist.
- Public ALB CIDR/WAF.
- Function URL auth không dùng `NONE`.
- Secret thật không đưa vào Git/Terraform output.

### 7.4 NetworkPolicy chưa enforce

Docs `03` yêu cầu NetworkPolicy, nhưng Terraform hiện mới tạo AWS SG. Kubernetes NetworkPolicy chưa có vì workload/bootstrap layer chưa làm.

Cần quyết định:

```text
AWS VPC CNI NetworkPolicy mode
or Calico
or Cilium
```

Nếu chưa có CNI policy engine, NetworkPolicy YAML sẽ không có tác dụng thực sự.

### 7.5 Observability chưa deploy

CloudWatch pipeline monitor đã có, nhưng Prometheus/Loki/Grafana chưa deploy. Vì vậy hiện chưa có:

- App metrics trong Prometheus.
- App logs trong Loki.
- Grafana dashboards.
- Alertmanager route vào Ingest Lambda.
- PrometheusRule tạo alert.

### 7.6 AI Engine chưa deploy

Terraform đã tạo IRSA role cho AI Engine, nhưng chưa có Kubernetes Deployment/Service.

Cần đảm bảo khi deploy:

- Service chỉ internal.
- Không expose public internet.
- Dùng `ai_engine_role_arn`.
- Chỉ đọc bounded evidence.
- Không có quyền SQS consume/delete.
- Không có Jira/Slack token nếu CDO Integration Layer sở hữu side effect.

### 7.7 AWS Load Balancer Controller chưa install

Terraform đã tạo IRSA role. Teammate cần cài Helm chart sau.

Nếu không cài controller:

```text
Kubernetes Ingress sẽ không tạo ALB.
Public app/API trong EKS sẽ chưa truy cập được.
```

---

## 8. Mapping với docs 02/03

Đã khớp với `02_infra_design.md` và `03_security_design.md` ở phần:

- AWS region `us-east-1`.
- EKS chosen.
- Private EKS nodes.
- SQS FIFO + DLQ.
- Ingest Lambda.
- DynamoDB incident state.
- S3 audit/evidence store.
- KMS encryption.
- Secrets Manager.
- CloudWatch pipeline monitor.
- IRSA roles cho Worker, AI Engine, AWS Load Balancer Controller, EBS CSI.
- Security group boundary cho app, aiops worker, ai engine, integration, observability, VPC endpoints.

Chưa khớp đầy đủ ở phần workload/runtime:

- Namespace isolation.
- Kubernetes RBAC.
- Kubernetes NetworkPolicy.
- Pod Security.
- ArgoCD/GitOps.
- Prometheus/Loki/Grafana/Alertmanager.
- AI Engine deployment.
- CDO Correlator Worker deployment.
- Demo app + Ingress.

Điều này là intentional cho Milestone 1:

```text
Terraform hiện là AWS infrastructure baseline, chưa phải full platform deployment.
```

---

## 9. Quick defense notes

```text
Chúng tôi không đưa raw metrics/logs vào SQS. SQS chỉ giữ alert event đã normalize.
```

```text
Raw telemetry vẫn nằm ở Prometheus/Loki/CloudWatch. AI Engine chỉ nên đọc bounded evidence theo tenant/service/env/window.
```

```text
CDO Correlator Worker dùng IRSA để thao tác SQS, DynamoDB, S3, Secrets Manager theo least privilege.
```

```text
AWS Load Balancer Controller chưa được Terraform install, nhưng IAM/IRSA đã sẵn sàng để Helm/GitOps cài controller.
```

```text
Milestone 1 chứng minh hạ tầng AWS và security baseline. Milestone tiếp theo là cluster bootstrap + GitOps workload deployment.
```

