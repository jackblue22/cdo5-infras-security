# TF1 Triage Hub - Terraform Infra Handoff

**Owner:** CDO-05  
**Vai trò của team này:** TF1 infrastructure + security baseline  
**Team phối hợp chính:** AIO-01  
**AWS region mặc định:** `us-east-1`  
**Environment đã test:** `dev`, `sandbox`  
**Environment tương thích CI/layout infra:** `sandbox`  
**Trạng thái hiện tại:** `sandbox` đã apply/verify thành công và đang chạy trên AWS  
**Ngày verify:** 2026-06-30

File này là bản handoff để teammate biết:

- CDO-05 đã làm tới đâu.
- Terraform hiện tạo được những gì.
- Hiện stack có đang chạy không.
- Còn thiếu gì về infrastructure/security.
- Team khác cần cung cấp gì để ghép vào.
- Kubernetes workload layer cần bổ sung những gì.
- Những rủi ro cần control khi apply lại.

---

## 1. TL;DR

Terraform trong folder này là **Milestone 1 AWS infrastructure baseline**, không phải full platform deployment.

Region triển khai mặc định là `us-east-1` và nên giữ nguyên cho tới khi cả CDO-05/AIO-01 cùng đổi. Lý do: AI Engine image handoff, cross-account ECR pull permission và lần verify EKS trước đó đều đang theo `us-east-1`.

Đã kiểm chứng trước đó với `dev`:

```text
terraform init: success
terraform validate: success
terraform apply: success
terraform plan sau apply: No changes
EKS cluster: created successfully
EKS nodes: 2 nodes Ready
EKS add-ons: vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver Running
terraform destroy: success, 117 resources destroyed
terraform state list sau destroy: empty
```

Đã kiểm chứng hiện tại với `sandbox`:

```text
terraform init: success
terraform validate: success
terraform apply: success, 117 added, 0 changed, 0 destroyed
terraform plan sau apply: No changes
aws_region: us-east-1
EKS cluster: tf1-triage-hub-sandbox ACTIVE, version 1.30
EKS nodes: 2 nodes Ready
EKS add-ons: aws-ebs-csi-driver, coredns, kube-proxy, vpc-cni
kube-system pods: Running
terraform state list count: 134 addresses
```

Hiện tại:

```text
Stack sandbox đang chạy trên AWS trong us-east-1.
Không destroy nếu team khác cần tiếp tục deploy workload lên EKS.
Nếu muốn tránh cost sau demo/handoff, chạy terraform destroy trong environments/sandbox.
```

Lệnh dùng để apply lại nếu sandbox đã bị destroy:

```powershell
cd D:\XBrain\Projects\xbrain-learners\capstone-phase2\temp\aiops\terraform\environments\sandbox
terraform init
terraform validate
terraform plan -input=false
terraform apply -auto-approve -input=false
```

Nếu muốn dùng đúng path đã apply/verify trước đó, thay `environments\sandbox` bằng `environments\dev`.

Lệnh destroy sau demo:

```powershell
terraform destroy -auto-approve -input=false
terraform state list
```

---

## 2. CDO-05 đã làm tới đâu?

CDO-05 đã hoàn thành phần **AWS infrastructure foundation** đủ để team khác gắn workload Kubernetes vào sau.

Đã làm:

| Mảng | Trạng thái | Ghi chú |
|---|---|---|
| Terraform module layout | Done | Có `environments/sandbox`, `dev`, `staging`, `prod` và các module riêng. |
| Region mặc định | Done | `us-east-1`, khớp yêu cầu hiện tại. |
| VPC/network baseline | Done | Public/private subnet, route table, Internet Gateway, VPC endpoints. |
| Security group baseline | Done | ALB, app, aiops worker, AI engine, integration, observability, VPC endpoints. |
| EKS cluster baseline | Done | EKS 1.30, managed node group, private worker nodes. |
| EKS managed add-ons | Done | `vpc-cni`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver`. |
| IAM/IRSA | Done | Worker, AI Engine, AWS Load Balancer Controller, EBS CSI. |
| Alert ingest | Done | Lambda ingest + Function URL + HMAC/timestamp/tenant validation. |
| Alert queue | Done | SQS FIFO + FIFO DLQ. |
| Incident state | Done | DynamoDB table. |
| Audit/evidence store | Done | S3 bucket with encryption/public-block/lifecycle baseline. |
| Secrets baseline | Done | Secrets Manager secret containers. |
| Encryption | Done | KMS key/alias support. |
| AWS pipeline monitor | Done | CloudWatch dashboard, alarms, log groups, SNS topic. |
| Apply verification | Done | `sandbox` apply succeeded, EKS nodes/add-ons healthy, post-apply plan has no changes. |
| Cleanup | Not yet for sandbox | `dev` test run was destroyed earlier; current `sandbox` stack is intentionally still running for handoff. |

Chưa làm trong scope Terraform hiện tại:

```text
Kubernetes workloads, Helm releases, ArgoCD apps, Prometheus/Loki/Grafana,
AI Engine deployment, CDO Worker deployment, app demo, NetworkPolicy YAML,
Pod Security labels, RBAC YAML, Service/Ingress manifests.
```

### 2.1 Mapping với folder `infra`

Folder `temp/aiops/infra` là reference về organization/path cho CI/CD và teammate, không phải source code chính để deploy. Folder `temp/aiops/terraform` vẫn là runtime source vì đây là bộ đã apply/verify được.

Mapping hiện tại:

| `infra` reference | `terraform` runtime source | Ghi chú |
|---|---|---|
| `environments/sandbox` | `environments/sandbox` | Đã thêm để team/CI có path tương tự `infra`. |
| `modules/networking` | `modules/networking` alias từ `modules/network` | Runtime module tự quản lý VPC, subnets, routes, NAT option và VPC endpoints. |
| `modules/eks` | `modules/eks` | Runtime module có EKS cluster, managed node group, OIDC provider và managed add-ons. |
| `modules/eks-addons` | `modules/eks` + future `k8s-bootstrap` | Managed add-ons đã có trong EKS module; Helm add-ons như ArgoCD/Prometheus/Loki/Grafana chưa thuộc Milestone 1. |
| `modules/incident-ingest` | `modules/incident-ingest` alias từ `modules/ingest-lambda` + root modules `queue/storage/security` | Runtime implementation đầy đủ hơn scaffold cũ: Lambda ingest, SQS FIFO/DLQ, DynamoDB, S3 audit, KMS/Secrets. |
| `modules/ecr` | `modules/ecr` | Tạo repo image cho workload tương lai. |
| `modules/github-oidc` | Chưa làm trong Milestone 1 | CI/CD OIDC nên làm ở phase deploy/pipeline. |
| `modules/external-secrets` | Chưa làm trong Milestone 1 | Secret containers đã ở AWS Secrets Manager; sync vào Kubernetes thuộc cluster bootstrap/workload phase. |

Không nên copy code từ `infra/modules/*` đè lên `terraform/modules/*`, vì scaffold `infra` thiếu nhiều phần security/queue/audit đã được verify trong bộ `terraform`.

---

## 3. Terraform tạo những gì khi apply?

### 3.1 Network

Module: `modules/network`

Sandbox compatibility path: `modules/networking` alias từ `modules/network`.

Tạo:

- VPC.
- Public subnets cho ALB/Ingress public sau này.
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
- Security group cho VPC endpoints.

Mục đích:

```text
EKS nodes chạy trong private subnet.
Workload gọi AWS APIs qua private endpoint khi có thể.
Giảm phụ thuộc public internet/NAT cho các service AWS nội bộ.
```

### 3.2 Security Groups

Module: `modules/security-groups`

Baseline SG:

| SG | Ý nghĩa | Rule chính |
|---|---|---|
| `public_alb` | Public HTTPS entrypoint | Internet/allowlist -> 443; egress chỉ tới app target port. |
| `app_workload` | Demo app/API sau ALB | Inbound từ `public_alb`; egress telemetry tới observability + VPC endpoints. |
| `aiops_worker` | CDO Correlator Worker | Không public inbound; egress tới AI Engine + AWS endpoints. |
| `ai_engine` | AI Engine internal API | Inbound chỉ từ aiops worker; không public internet. |
| `integration` | Jira/Slack integration boundary | Egress tới AWS endpoints và external SaaS nếu cần NAT/egress proxy. |
| `observability` | Prometheus/Loki/Grafana/OTel | Ingest/scrape từ app/workload; không public unauthenticated. |
| `vpc_endpoints` | AWS API private endpoint boundary | 443 từ workload SGs. |

Quan trọng:

```text
SG chỉ là network boundary cấp VPC.
Tenant isolation vẫn cần tenant_id, IAM condition, S3 prefix, DynamoDB key, evidence query scope, RBAC và NetworkPolicy.
```

### 3.3 EKS

Module: `modules/eks`

Tạo:

- EKS cluster: default name `tf1-triage-hub-dev`.
- Kubernetes version: `1.30`.
- Managed node group: `2 x m7i-flex.large`.
- AMI type: `AL2023_x86_64_STANDARD`.
- EKS control plane log group.
- Managed add-ons:
  - `vpc-cni`
  - `kube-proxy`
  - `coredns`
  - `aws-ebs-csi-driver`
- OIDC provider.
- EBS CSI IRSA role.

Đã verify sau apply:

```text
kubectl get nodes -o wide -> 2 nodes Ready
kubectl get pods -A -> kube-system pods Running
aws eks list-addons -> 4 add-ons present
```

### 3.4 IAM / IRSA

Module: `modules/iam-irsa`

Tạo IRSA roles:

| Role | Kubernetes ServiceAccount dự kiến | Quyền chính |
|---|---|---|
| Correlator Worker IRSA | `aiops/correlator-worker` | Consume SQS FIFO, update DynamoDB, read/write S3 evidence, read required secrets, KMS. |
| AI Engine IRSA | `ai-engine/ai-engine-api` | Read bounded S3 evidence, read service token secret, optional Bedrock invoke. |
| AWS LBC IRSA | `kube-system/aws-load-balancer-controller` | Create/manage ALB, target groups, listeners, SG rules theo AWS Load Balancer Controller policy. |
| EBS CSI IRSA | `kube-system/ebs-csi-controller-sa` | Create/attach/detach EBS volumes cho PVC. |

Chú ý:

```text
Terraform đã tạo IAM role/policy cho AWS Load Balancer Controller.
Terraform chưa cài AWS Load Balancer Controller Helm chart.
```

Khi team cài controller, ServiceAccount phải dùng đúng annotation:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: <aws_load_balancer_controller_role_arn>
```

### 3.5 Alert Ingest

Module: `modules/ingest-lambda`

Sandbox compatibility path: `modules/incident-ingest` alias từ `modules/ingest-lambda`.

Tạo:

- Ingest Lambda.
- Lambda Function URL.
- Lambda IAM role/policy.
- Lambda log group.

Lambda hiện xử lý:

- Nhận Alertmanager webhook.
- Verify HMAC nếu secret đã set.
- Check timestamp chống replay.
- Validate payload.
- Check `X-Tenant-Id` match `tenant_id`.
- Normalize alert event.
- Gửi message vào SQS FIFO với dedup/grouping.

Trade-off hiện tại:

```text
Function URL đủ cho MVP/demo.
API Gateway là prod hardening option nếu webhook public thật và cần throttling/auth/API management mạnh hơn.
```

### 3.6 Queue / State / Audit

Modules: `modules/queue`, `modules/storage`

Tạo:

- SQS FIFO incident queue.
- SQS FIFO DLQ.
- DynamoDB `incident_state`.
- S3 audit/evidence bucket.

Data boundary:

```text
SQS = alert event đã normalize.
DynamoDB = workflow state/idempotency/ticket pointer.
S3 = audit/evidence artifacts.
Prometheus/Loki/CloudWatch = raw telemetry source.
```

Không đưa raw metrics/logs vào SQS.

### 3.7 Secrets / KMS

Module: `modules/security`

Tạo:

- KMS key/alias.
- Secrets Manager secret containers:
  - webhook signing key
  - service auth token
  - Jira API token
  - Slack webhook/token
  - Grafana admin password

Chưa làm:

```text
Chưa set secret value thật.
Chưa sync secret vào Kubernetes bằng External Secrets Operator/CSI.
```

### 3.8 CloudWatch Monitoring

Module: `modules/monitoring`

Tạo:

- CloudWatch dashboard cho pipeline health.
- SNS topic cho alarm.
- Alarms cho:
  - Lambda errors/throttles.
  - SQS oldest message age.
  - SQS DLQ visible messages.
  - DynamoDB read/write throttles.
- Log groups cho các component AWS/pipeline.

Không thay thế:

```text
Prometheus/Loki/Grafana vẫn cần deploy trong Kubernetes workload layer.
```

---

## 4. Hiện tại còn thiếu gì phía CDO infrastructure/security?

Các mục dưới đây là phần CDO-05 vẫn cần làm hoặc cần quyết định nếu muốn đi từ Milestone 1 sang platform chạy được end-to-end.

### 4.1 Remote Terraform state

Hiện Terraform dùng local state.

Thiếu:

- S3 backend bucket cho Terraform state.
- DynamoDB lock table.
- Backend config theo `dev/staging/prod`.
- Quy trình ai được apply/destroy.

Rủi ro nếu không làm:

```text
Hai người apply cùng lúc hoặc copy state sai có thể tạo conflict, drift, hoặc orphan resources.
```

Recommendation:

```text
Trước khi nhiều teammate cùng dùng, tạo remote backend S3 + DynamoDB lock.
```

### 4.2 Kubernetes bootstrap manifests

Thiếu folder riêng kiểu:

```text
k8s-bootstrap/
cluster-bootstrap/
```

Cần bổ sung:

- Namespace `app`.
- Namespace `aiops`.
- Namespace `ai-engine`.
- Namespace `observability`.
- Pod Security labels.
- RBAC.
- ServiceAccounts + IRSA annotations.
- NetworkPolicy default deny + allowlist.
- ResourceQuota/LimitRange.

### 4.3 NetworkPolicy engine

Docs `03` yêu cầu NetworkPolicy, nhưng NetworkPolicy chỉ có tác dụng nếu CNI/policy engine support.

Cần quyết định:

| Option | Ghi chú |
|---|---|
| AWS VPC CNI NetworkPolicy | Native AWS hơn, hợp EKS. Cần enable đúng config/add-on. |
| Calico | Phổ biến, dễ demo NetworkPolicy. |
| Cilium | Mạnh hơn, có observability/network security tốt, nhưng phức tạp hơn. |

Nếu chưa quyết:

```text
NetworkPolicy YAML chỉ là intent, chưa phải enforcement thật.
```

### 4.4 Admission control / Pod Security

Thiếu hard guardrail để chặn pod nguy hiểm.

Cần tối thiểu:

- Pod Security Admission labels:
  - `pod-security.kubernetes.io/enforce=restricted` cho namespace nhạy cảm nếu workload tương thích.
  - Có thể dùng `baseline` trước nếu chart chưa tương thích `restricted`.
- Không privileged pods.
- Không hostPath.
- Không hostNetwork trừ add-on cần thiết.
- `runAsNonRoot` nếu image hỗ trợ.
- Read-only root filesystem nếu image hỗ trợ.
- Drop Linux capabilities nếu có thể.

Prod-like hơn:

- Kyverno hoặc Gatekeeper để enforce policy.
- Image registry allowlist.
- Require resource requests/limits.
- Block `latest` tag cho production.
- Require IRSA annotation cho workload cần AWS access.

### 4.5 AWS Load Balancer Controller

Terraform chỉ tạo IRSA. Cần cài Helm chart.

Thiếu:

- Helm release hoặc ArgoCD Application cho AWS Load Balancer Controller.
- ServiceAccount annotated bằng `aws_load_balancer_controller_role_arn`.
- IngressClass.
- Test Ingress tạo ALB.

Nếu thiếu:

```text
Kubernetes Ingress sẽ không tự tạo ALB.
Public app/API chưa truy cập được.
```

### 4.6 Observability stack

Thiếu:

- Prometheus.
- Alertmanager.
- Loki.
- Grafana.
- OpenTelemetry Collector nếu dùng.
- PrometheusRule.
- ServiceMonitor/PodMonitor.
- Grafana dashboards.
- Retention/storage config.

Security cần chú ý:

- Grafana không public unauthenticated.
- Prometheus/Loki không expose public.
- Tenant/service/env labels phải nhất quán.
- Log redaction/token redaction.
- Retention giới hạn để tránh cost.

### 4.7 AI Engine deployment

Terraform đã có IRSA role nhưng chưa deploy workload.

Thiếu:

- Namespace `ai-engine`.
- ServiceAccount `ai-engine-api`.
- Deployment dùng image AIO-01.
- ClusterIP Service nội bộ.
- Health/readiness probes.
- NetworkPolicy chỉ cho `aiops` gọi vào.
- Secret/service auth wiring.

AI image từ AIO-01:

```text
image: 589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0
pinned digest: 589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine@sha256:ed9d9ca831aa70865e175a611359610c66be5cb56fd33b0487ac687fc4b14f70
containerPort: 8080
GET /healthz
GET /readyz
GET /metrics
POST /v1/triage
```

Security rule:

```text
AI Engine không được public internet.
AI Engine không được có quyền consume/delete SQS.
AI Engine không giữ Jira/Slack token nếu CDO Integration Layer sở hữu side effect.
AI Engine chỉ đọc bounded evidence theo tenant/service/env/window.
```

### 4.8 CDO Correlator Worker deployment

Terraform đã có IRSA role nhưng chưa deploy workload.

Thiếu:

- Namespace `aiops`.
- ServiceAccount `correlator-worker`.
- Deployment/worker consumer.
- HPA hoặc replica strategy.
- Config SQS URL, DynamoDB table, S3 bucket, AI Engine URL.
- Retry/backoff/idempotency handling trong app.
- Metrics `/metrics` nếu có.
- NetworkPolicy cho egress tới AI Engine + AWS endpoints.

Security rule:

```text
Worker được quyền SQS/DynamoDB/S3/Secrets theo IRSA.
Worker không được cluster-admin.
Worker không được đọc toàn bộ Kubernetes Secrets.
```

### 4.9 Evidence access layer

Docs `03` nói AI chỉ nên đọc bounded evidence. Hiện Terraform mới tạo S3/IAM baseline.

Cần chọn một trong hai:

| Pattern | Ai cần làm | Ghi chú |
|---|---|---|
| S3 evidence bundle | CDO + AIO | Worker tạo bounded bundle trong S3, AI đọc đúng object/prefix. Dễ cho MVP. |
| Evidence proxy | CDO platform | AI gọi internal proxy, proxy enforce tenant/service/env/window. Prod-like hơn. |

MVP recommendation:

```text
Dùng S3 evidence bundle trước.
Evidence proxy để sau nếu còn thời gian.
```

### 4.10 Jira/Slack integration

Terraform đã tạo secret containers, chưa có integration runtime.

Thiếu:

- Jira/Slack token thật.
- Integration Lambda hoặc worker/pod.
- Idempotency check trước khi tạo ticket/message.
- Rate limit/backoff.
- Audit event lưu vào S3/DynamoDB.
- Dry-run mode nếu demo không dùng token thật.

Security rule:

```text
Token Jira/Slack không cấp cho AI Engine nếu CDO owns integration.
```

---

## 5. Team khác cần cung cấp gì để ghép vào?

### 5.1 AIO-01 cần cung cấp

Đã có:

- AI Engine image URI.
- Pinned digest.
- Health endpoints.
- Triage endpoint.
- Cross-account ECR pull permission cho CDO account.

Cần confirm thêm:

| Cần từ AIO-01 | Vì sao cần |
|---|---|
| Final request/response contract của `/v1/triage` | Worker cần gọi đúng schema. |
| Required env vars của AI Engine | Deployment cần config đúng. |
| Required secrets/config | Biết secret nào cần mount, secret nào không. |
| CPU/memory request/limit khuyến nghị | Để set Kubernetes resource limits. |
| Readiness behavior | Để set readiness/liveness probe chuẩn. |
| Bedrock có dùng thật không | Nếu có cần enable Bedrock IAM policy, budget, region. |
| AI cần evidence dạng S3 URI hay inline payload | Quyết định Worker tạo bundle kiểu nào. |
| AI có write artifact lại S3 không | Nếu có cần scope IAM S3 write prefix. |
| Error codes/retryable errors | Worker cần biết khi nào retry, khi nào đưa DLQ/manual. |

### 5.2 Team app/demo cần cung cấp

Cần:

- Container image demo app.
- Port app expose.
- Health endpoint.
- Metrics endpoint.
- Log format.
- Tenant labels:
  - `tenant_id`
  - `service`
  - `env`
  - `severity` nếu liên quan alert
- Kubernetes manifests hoặc Helm chart.
- Expected Ingress path/domain.
- Prometheus scrape annotations hoặc ServiceMonitor config.

Vì sao:

```text
Prometheus/Loki/Grafana và alert rules phụ thuộc vào label/port/path của app.
```

### 5.3 Team observability cần cung cấp

Cần:

- Prometheus stack chart/version.
- Loki chart/version.
- Grafana chart/version.
- Alertmanager config.
- PrometheusRule cho demo incident.
- Grafana dashboard JSON.
- Retention target.
- StorageClass/PVC requirement.
- Log label strategy.
- Metric naming convention.

Security cần confirm:

- Grafana access: internal only, port-forward, VPN, hay public with auth.
- Prometheus/Loki có expose không.
- Alertmanager webhook target là Lambda Function URL hay internal route.

### 5.4 Team integration cần cung cấp

Cần:

- Jira project/key.
- Jira API token hoặc dry-run mode.
- Slack workspace/channel/webhook hoặc dry-run mode.
- Message/ticket template.
- Rate limit expectation.
- Idempotency rule:
  - create once per incident?
  - update existing ticket/thread?
  - close ticket khi alert resolved?

Security cần confirm:

```text
Token thật phải nằm trong Secrets Manager, không nằm trong Git/Helm values plaintext.
```

### 5.5 Team GitOps/deployment cần cung cấp

Cần:

- ArgoCD install method.
- Git repo/path structure cho app manifests.
- Environments:
  - `dev`
  - `staging`
  - `prod`
- Promotion flow.
- Rollback rule.
- Image tag/digest policy.
- Secret sync method:
  - External Secrets Operator
  - Secrets Store CSI Driver
  - manual Kubernetes Secret cho demo

Recommended repo shape:

```text
k8s-bootstrap/
  namespaces/
  rbac/
  network-policies/
  pod-security/
  service-accounts/
  aws-load-balancer-controller/

gitops/
  argocd/
  apps/
    ai-engine/
    correlator-worker/
    observability/
    demo-app/
```

---

## 6. Kubernetes layer cần bổ sung cụ thể

### 6.1 Namespaces

Cần tạo:

```text
app
aiops
ai-engine
observability
```

Gợi ý labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/part-of: tf1-triage-hub
    environment: dev
    owner: cdo-05
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

Dùng `baseline` trước nếu chart chưa tương thích `restricted`. Khi workload ổn thì nâng namespace nhạy cảm lên `restricted`.

### 6.2 ServiceAccounts + IRSA

Cần tạo:

```text
aiops/correlator-worker
ai-engine/ai-engine-api
kube-system/aws-load-balancer-controller
```

Mỗi ServiceAccount phải annotate đúng role ARN từ Terraform output.

### 6.3 RBAC

Tối thiểu:

- Worker chỉ được read metadata cần thiết trong namespace liên quan.
- Không cấp `cluster-admin`.
- Không cấp quyền read all Kubernetes Secrets.
- Không cấp `pods/exec`, `pods/portforward` nếu không cần.
- Observability có quyền scrape/read endpoint theo chart requirement.

### 6.4 NetworkPolicy

Baseline:

- Default deny ingress/egress cho:
  - `aiops`
  - `ai-engine`
  - `observability`
- Allow `aiops` -> `ai-engine:8080`.
- Allow `app` -> `observability` ingest/scrape.
- Allow `observability` -> scrape targets.
- Allow workload -> kube-dns.
- Allow workload -> AWS endpoints nếu policy engine kiểm soát được egress.
- Deny public/other namespace -> AI Engine.

### 6.5 ResourceQuota / LimitRange

Cần để tránh một workload ăn hết node:

- CPU/memory requests.
- CPU/memory limits.
- PVC limits nếu Prometheus/Loki dùng PVC.
- Object count giới hạn cho demo namespace nếu cần.

### 6.6 AWS Load Balancer Controller

Cần:

- Helm chart install.
- ServiceAccount annotated IRSA.
- IngressClass `alb`.
- Test Ingress cho demo app.

Ingress chỉ nên route app/demo API, không route:

```text
AI Engine
Prometheus
Loki
Grafana admin
Worker
```

### 6.7 ArgoCD

Cần:

- Install ArgoCD.
- App of apps hoặc Application per component.
- Sync order:
  1. namespaces/RBAC/pod-security/network-policy
  2. AWS Load Balancer Controller
  3. observability stack
  4. app demo
  5. AI Engine
  6. CDO Worker
  7. alert rules/integration

---

## 7. Security checklist còn thiếu trước khi defense

| Control | Hiện trạng | Cần bổ sung |
|---|---|---|
| IAM least privilege | Terraform đã có baseline | Review lại sau khi workload final. |
| IRSA | Role đã có | Tạo ServiceAccount annotation trong Kubernetes. |
| Secrets Manager | Secret containers đã có | Set value thật + secret sync method. |
| Network SG | Đã có baseline | Verify lại khi ALB/Ingress thật được tạo. |
| NetworkPolicy | Chưa có | Chọn policy engine + apply default deny/allowlist. |
| Pod Security | Chưa có | Namespace labels + policy validation. |
| Admission control | Chưa có | Optional Kyverno/Gatekeeper nếu cần prod-like. |
| Audit S3 | Đã có baseline khi apply | Confirm retention/Object Lock claim trước defense. |
| CloudWatch monitor | Đã có AWS-side | Bổ sung Prometheus/Loki/Grafana. |
| Tenant isolation test | Chưa có | Test tenant mismatch, cross-tenant evidence query. |
| AI public exposure | Chưa deploy | Khi deploy, Service phải internal only. |
| Jira/Slack token isolation | Secret container đã có | Không cấp token cho AI Engine nếu CDO owns integration. |

---

## 8. Những điểm cần nói rõ khi handoff

### 8.1 Sandbox stack đang chạy

Hiện tại sandbox đã được apply thành công và đang tồn tại trên AWS:

```text
AWS account: 056755224027
Region: us-east-1
Cluster: tf1-triage-hub-sandbox
Terraform root: environments/sandbox
Post-apply plan: No changes
EKS nodes: 2 Ready
EKS add-ons: aws-ebs-csi-driver, coredns, kube-proxy, vpc-cni
```

Không destroy nếu team khác cần deploy workload tiếp lên cluster này. Khi demo/handoff xong và muốn tránh cost, chạy:

```powershell
cd D:\XBrain\Projects\xbrain-learners\capstone-phase2\temp\aiops\terraform\environments\sandbox
terraform destroy -auto-approve -input=false
terraform state list
```

### 8.2 Apply một cú có được không?

Được nếu:

- Chạy từ đúng `environments/sandbox` hoặc `environments/dev`.
- State sạch hoặc dùng đúng remote/shared state.
- AWS account/region `us-east-1` không còn resource trùng tên từ lần apply khác.

Không nên nếu:

- Copy folder sang repo khác nhưng không copy state.
- Có người khác đã apply cùng name prefix.
- Chưa thống nhất remote backend.
- Sandbox hiện đang chạy nhưng teammate dùng một state khác, vì khi đó Terraform có thể cố tạo resource trùng tên.

### 8.3 Terraform không deploy full Kubernetes platform

Terraform hiện dừng ở AWS infra baseline. Phần sau nên do `k8s-bootstrap` hoặc ArgoCD quản lý.

Lý do:

```text
Tránh một apply vừa tạo EKS vừa cài Helm/CRD/workload gây race condition.
Tách rõ AWS infra layer và Kubernetes workload layer.
```

---

## 9. Có cần sửa docs 02/03 không?

Hiện tại **không cần sửa lớn `02_infra_design.md` hoặc `03_security_design.md`**.

Lý do:

- `02` đã nói Milestone 1 là AWS infra + security baseline, chưa deploy workload Kubernetes.
- `02` đã nói Terraform từng apply/verify EKS/node/add-ons healthy; hiện sandbox cũng đã apply lại thành công để handoff.
- `03` đã cover IAM, secrets, network, audit, tenant isolation, NetworkPolicy, Pod Security/RBAC ở mức design.

Nếu muốn làm docs chặt hơn nữa, chỉ cần bổ sung nhẹ sau này:

- Trong `02`: link tới `temp/aiops/terraform/INFRA_HANDOFF.md` như evidence handoff.
- Trong `03`: thêm note rõ “NetworkPolicy/Pod Security chưa được Terraform apply ở Milestone 1; thuộc cluster bootstrap evidence”.

Không cần đổi design chính.

---

## 10. Defense summary

```text
CDO-05 đã hoàn thành và verify AWS infrastructure baseline bằng Terraform.
```

```text
Stack dev đã được destroy sau verify; stack sandbox hiện đang chạy để team khác tiếp tục deploy workload.
```

```text
Apply/handoff path hiện tại: terraform/environments/sandbox, region us-east-1, cluster tf1-triage-hub-sandbox.
```

```text
Terraform tạo EKS, private networking, SG boundaries, SQS FIFO/DLQ, DynamoDB, S3 audit, KMS, Secrets Manager, Lambda ingest, CloudWatch monitor và IRSA roles.
```

```text
Terraform chưa deploy Kubernetes workloads. Namespace/RBAC/NetworkPolicy/Pod Security/ArgoCD/Prometheus/Loki/Grafana/AI Engine/Worker là lớp tiếp theo.
```

```text
Team khác cần cung cấp workload manifests/images/contracts/secrets/observability rules để ghép vào infrastructure này.
```

```text
Security boundary chính: AI Engine không public, không consume SQS, không giữ Jira/Slack token; Worker dùng IRSA least privilege; raw telemetry không đi vào SQS.
```
