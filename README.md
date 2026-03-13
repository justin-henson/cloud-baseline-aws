
# Cloud Baseline (AWS) — Terraform, Private EC2 via SSM, ALB front door

Secure baseline AWS infrastructure using Terraform. Demonstrates production-minded patterns: private compute (no SSH), controlled ingress via ALB, and repeatable create/destroy for interview demos.

## What this demonstrates
- VPC + public/private subnets across 2 AZs
- Private EC2 managed via **AWS Systems Manager (SSM)** (no inbound SSH)
- Application Load Balancer (ALB) → Target Group → private instance on port 8080
- IAM instance profile with least-privilege managed policy for SSM
- Interface VPC endpoints for SSM (no NAT required)
- Consistent tagging + clean repo structure + CI checks

## Architecture
```mermaid
flowchart LR
  Internet((Internet)) --> ALB[ALB :80]
  ALB --> TG[Target Group :8080]
  TG --> EC2[Private EC2 :8080]
  EC2 -->|SSM Agent| SSM[(AWS SSM)]
  EC2 --> VPCE1[vpce: ssm]
  EC2 --> VPCE2[vpce: ec2messages]
  EC2 --> VPCE3[vpce: ssmmessages]
  subgraph VPC
    ALB
    TG
    EC2
    VPCE1
    VPCE2
    VPCE3
  end
  ```

## Proof (how to verify it works)

After terraform apply, Terraform outputs the ALB DNS name and the EC2 instance id.

1) Confirm the ALB serves the demo page
```bash
curl -s "http://$(terraform output -raw alb_dns_name)" | head
```
2) Confirm the target is healthy

```bash
aws elbv2 describe-target-health \
  --region us-east-1 \
  --target-group-arn "$(terraform output -raw alb_target_group_arn)"
```

3) Confirm SSM access works (no SSH)
```bash
aws ssm start-session \
  --region us-east-1 \
  --target "$(terraform output -raw app_instance_id)"
```
## Inside the instance:
```bash
sudo systemctl status nz-demo --no-pager
curl -s http://127.0.0.1:8080 | head
exit
```
## Run / Destroy 
Prereqs

### Run
```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan -var-file=env/dev.tfvars
terraform apply -var-file=env/dev.tfvars
```
### Destroy
```bash
terraform destroy -var-file=env/dev.tfvars
```
## Security / Cost

### Security
- No inbound SSH to the instance (SSM Session Manager only)
- App EC2 security group allows inbound only from the ALB security group
- IMDSv2 enforced (`http_tokens = "required"`)
- VPC endpoints keep SSM management traffic private inside the VPC

### Cost (what drives spend)
- ALB: hourly + LCU usage (often the biggest line item in demos)
- EC2 + EBS: instance hours + storage
- VPC Interface Endpoints: hourly per endpoint + data processing

## Repo structurei
```bash
.
├── .github/
│   └── workflows/
│       └── terraform-ci.yml
├── docs/
│   ├── architecture.md
│   ├── cost.md
│   ├── dr.md
│   ├── runbook.md
│   └── security.md
├── env/
│   ├── dev.tfvars.example
│   └── dev.tfvars            
├── scripts/
│   ├── bootstrap.sh
│   ├── destroy.sh
│   ├── up.sh                 
│   └── down.sh               
├── alb.tf
├── compute.tf
├── locals.tf
├── main.tf
├── outputs.tf
├── ssm_endpoints.tf
├── variables.tf
├── versions.tf
└── README.md
```
## What I’d improve next

- Add HTTPS using ACM + 443 listener and redirect 80 → 443
- Replace single EC2 with an Auto Scaling Group (ASG) behind the target group
- Add CloudWatch alarms + dashboards (ALB 5XX, target health, instance CPU/mem)
- Add ALB access logs to S3 and structured app logging to CloudWatch
- Add remote state + locking (S3 + DynamoDB) for team workflows
- Add CI checks: `terraform fmt`, `terraform validate`, `tflint`, basic security scanning (e.g., `checkov`)
