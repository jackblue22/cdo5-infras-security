# TF1 Triage Hub - AWS Terraform

Terraform trong folder này dựng **Milestone 1 infrastructure baseline** cho CDO-05:

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

Terraform chưa deploy Kubernetes workload như Demo App, Prometheus, Loki, Grafana, CDO Correlator Worker hoặc AI Engine. Các phần đó thuộc workload/deployment layer sau khi infra base đã sẵn sàng.

## Tạo Ra Gì?

| Nhóm | Resource |
|---|---|
| Network | VPC, public/private subnets, route tables, VPC endpoints, optional NAT Gateway |
| Runtime | EKS cluster, managed node group, EKS managed add-ons, ECR repositories |
| Alert reliability | Ingest Lambda, SQS FIFO incident queue, FIFO DLQ |
| State/audit | DynamoDB `incident_state`, S3 audit/evidence bucket |
| Security | KMS key, Secrets Manager placeholders, IAM least privilege, IRSA roles |
| Monitoring | CloudWatch log groups, alarms, SNS topic, dashboard |
| Optional prod controls | WAF WebACL, CloudTrail |

## Current Demo Defaults

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

## Cách Chạy

```powershell
cd D:\XBrain\Projects\xbrain-learners\capstone-phase2\temp\aiops\terraform
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

## Validation Đã Chạy

Lần apply gần nhất đã thành công với:

```text
terraform apply from empty state: success, one-shot, no manual mid-run fix
terraform plan after apply: No changes
node group: ACTIVE, 2 x m7i-flex.large
AMI: AL2023_x86_64_STANDARD
add-ons: vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver
kubectl nodes: 2 Ready
kube-system pods: aws-node, kube-proxy, coredns, ebs-csi Running
terraform destroy: Destroy complete, 117 resources destroyed
terraform state list: empty
```

## Notes Quan Trọng

- EKS add-ons được tách thứ tự:
  - Pre-node: `vpc-cni`, `kube-proxy`
  - Post-node: `coredns`, `aws-ebs-csi-driver`
- EBS CSI dùng IRSA riêng: `tf1-triage-hub-dev-ebs-csi-driver-irsa`.
- SQS là FIFO queue, không phải standard queue.
- SQS chỉ giữ alert event, không giữ raw metrics/logs.
- DynamoDB giữ workflow state/idempotency/ticket pointer.
- S3 giữ bounded evidence/audit artifacts.
- AI Engine không public internet; chỉ nên gọi nội bộ từ CDO Worker.

## AI Image Note

AIO-01 image hiện ở ECR `us-east-1`:

```text
589077667575.dkr.ecr.us-east-1.amazonaws.com/tf1-ai-triage-engine:v1.0.0
```

Terraform hiện mặc định dựng EKS private nodes ở `us-east-1`, cùng region với AIO ECR image. Vì vậy workload AI Engine có thể dùng image handoff trực tiếp nếu cross-account pull permission vẫn còn hiệu lực.

Nếu sau này đổi infra sang region khác, cần chọn một trong ba hướng:

1. Copy/replicate image AIO vào ECR cùng region với EKS. Recommended cho private nodes.
2. Bật `enable_nat_gateway = true` để private nodes pull cross-region/public ECR. Chạy được nhưng tốn cost hơn.
3. Giữ toàn bộ runtime ở `us-east-1` nếu team thống nhất chạy cùng region với AIO/Bedrock.
