<div align="center">

# ☁️ Cloud-Native DevOps Platform

<p align="center">
  <img src="https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform" />
  <img src="https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes" />
  <img src="https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white" alt="AWS" />
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker" />
  <img src="https://img.shields.io/badge/GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white" alt="GitHub Actions" />
  <img src="https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white" alt="Prometheus" />
  <img src="https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white" alt="Grafana" />
  <img src="https://img.shields.io/badge/ArgoCD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white" alt="ArgoCD" />
</p>

<p align="center">
  <strong>End-to-end infrastructure-as-code platform for deploying and managing cloud-native applications</strong>
</p>

<p align="center">
  <a href="#architecture">Architecture</a> •
  <a href="#modules">Modules</a> •
  <a href="#features">Features</a> •
  <a href="#getting-started">Getting Started</a> •
  <a href="#security">Security</a> •
  <a href="#monitoring">Monitoring</a>
</p>

</div>

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Modules](#modules)
- [Features](#features)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Security](#security)
- [Monitoring](#monitoring)
- [Contributing](#contributing)

---

## 🔭 Overview

This repository contains a **production-grade, cloud-native DevOps platform** built on AWS with Terraform, Kubernetes (EKS), and GitOps principles. It provides a complete infrastructure foundation for running containerized applications with enterprise security, observability, and reliability patterns.

### Key Highlights

- **Multi-Environment Strategy**: Isolated dev, staging, and production environments with environment-specific configurations
- **GitOps-Driven Deployments**: ArgoCD-based continuous delivery with automated sync and drift detection
- **Security-First Design**: Private subnets, encryption at rest/transit, least-privilege IAM, network policies
- **Full Observability Stack**: Prometheus, Grafana, AlertManager, and CloudWatch dashboards
- **Automated CI/CD**: GitHub Actions workflows for Terraform, Docker builds, and security scanning
- **Cost Optimization**: Spot instances, autoscaling, lifecycle policies, and resource rightsizing

---

## 🏗️ Architecture

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                AWS Cloud                                     │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                           Management Account                             │ │
│  │                     (IAM, Route53, CloudTrail)                           │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│           ┌────────────────────────┼────────────────────────┐                │
│           ▼                        ▼                        ▼                │
│  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────┐            │
│  │   Dev Account    │  │ Staging Account  │  │  Prod Account    │            │
│  │                  │  │                  │  │                  │            │
│  │  ┌────────────┐  │  │  ┌────────────┐  │  │  ┌────────────┐  │            │
│  │  │    VPC     │  │  │  │    VPC     │  │  │  │    VPC     │  │            │
│  │  │  3 AZs     │  │  │  │  3 AZs     │  │  │  │  3 AZs     │  │            │
│  │  │            │  │  │  │            │  │  │  │            │  │            │
│  │  │ ┌────────┐ │  │  │  │ ┌────────┐ │  │  │  │ ┌────────┐ │  │            │
│  │  │ │ Public │ │  │  │  │ │ Public │ │  │  │  │ │ Public │ │  │            │
│  │  │ │Subnet  │ │  │  │  │ │Subnet  │ │  │  │  │ │Subnet  │ │  │            │
│  │  │ │(ALB)   │ │  │  │  │ │(ALB)   │ │  │  │  │ │(ALB)   │ │  │            │
│  │  │ └────────┘ │  │  │  │ └────────┘ │  │  │  │ └────────┘ │  │            │
│  │  │ ┌────────┐ │  │  │  │ ┌────────┐ │  │  │  │ ┌────────┐ │  │            │
│  │  │ │Private │ │  │  │  │ │Private │ │  │  │  │ │Private │ │  │            │
│  │  │ │(EKS)   │ │  │  │  │ │(EKS)   │ │  │  │  │ │(EKS)   │ │  │            │
│  │  │ └────────┘ │  │  │  │ └────────┘ │  │  │  │ └────────┘ │  │            │
│  │  │ ┌────────┐ │  │  │  │ ┌────────┐ │  │  │  │ ┌────────┐ │  │            │
│  │  │ │Private │ │  │  │  │ │Private │ │  │  │  │ │Private │ │  │            │
│  │  │ │(RDS)   │ │  │  │  │ │(RDS)   │ │  │  │  │ │(RDS)   │ │  │            │
│  │  │ └────────┘ │  │  │  │ └────────┘ │  │  │  │ └────────┘ │  │            │
│  │  └────────────┘  │  │  └────────────┘  │  │  └────────────┘  │            │
│  └─────────────────┘  └──────────────────┘  └──────────────────┘            │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                     Shared Services (Prod Account)                       │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐    │ │
│  │  │  S3      │  │ ECR      │  │ Route53  │  │  CloudFront          │    │ │
│  │  │  State   │  │ Images   │  │  DNS     │  │  CDN                 │    │ │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────────────────┘    │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Architecture Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Compute** | Amazon EKS | Kubernetes orchestration with managed node groups |
| **Networking** | VPC, ALB, CloudFront | Multi-AZ networking with CDN |
| **Database** | RDS PostgreSQL | Multi-AZ relational database with encryption |
| **Cache** | ElastiCache Redis | High-performance caching layer |
| **Storage** | S3 + CloudFront | Static assets with lifecycle policies |
| **IAM** | IAM Roles, IRSA | Least-privilege access with service accounts |
| **GitOps** | ArgoCD | Declarative continuous delivery |
| **Monitoring** | Prometheus + Grafana | Metrics collection and visualization |
| **CI/CD** | GitHub Actions | Automated build, test, and deploy |
| **Security** | Trivy, tfsec, Security Groups | Vulnerability scanning and network security |

---

## 📦 Modules

### Terraform Modules

| Module | Description | Key Resources |
|--------|-------------|---------------|
| [`vpc`](terraform/modules/vpc/) | VPC Networking | VPC, subnets, NAT GW, IGW, VPC endpoints, flow logs |
| [`eks`](terraform/modules/eks/) | EKS Cluster | Managed node groups, Fargate, OIDC, cluster autoscaler |
| [`rds`](terraform/modules/rds/) | PostgreSQL Database | Multi-AZ RDS, encryption, parameter groups, backups |
| [`redis`](terraform/modules/redis/) | ElastiCache Redis | Cluster mode, encryption, parameter group |
| [`s3`](terraform/modules/s3/) | S3 + CloudFront | Versioning, encryption, lifecycle, CDN |
| [`iam`](terraform/modules/iam/) | IAM Resources | Roles, policies, IRSA, least-privilege access |
| [`monitoring`](terraform/modules/monitoring/) | Observability | Prometheus, Grafana, AlertManager, CloudWatch |

### Kubernetes Components

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| API Gateway | `apps` | Sample microservice with HPA and ingress |
| Network Policies | `all` | Pod-to-pod security policies |
| Prometheus | `monitoring` | Metrics collection and alerting |
| Grafana | `monitoring` | Metrics visualization and dashboards |
| cert-manager | `cert-manager` | Automatic SSL certificate provisioning |
| ArgoCD | `argocd` | GitOps continuous delivery |

---

## ✨ Features

### Core Infrastructure

- **Infrastructure as Code**: 100% Terraform-managed with modular design
- **Multi-Environment**: Isolated dev/staging/prod with workspace-based state management
- **Private Networking**: All workloads run in private subnets with controlled egress
- **Encryption Everywhere**: At-rest (KMS) and in-transit (TLS) encryption

### GitOps & CI/CD

- **GitOps Deployment**: ArgoCD with automated sync, prune, and self-healing
- **CI/CD Pipelines**: GitHub Actions for Terraform plan/apply and Docker builds
- **Security Scanning**: Trivy container scanning, tfsec IaC scanning
- **Automated Testing**: Terraform validate, plan verification on PRs

### Observability

- **Metrics**: Prometheus with ServiceMonitor CRDs
- **Dashboards**: Grafana with pre-configured dashboards
- **Alerting**: AlertManager with PagerDuty/Slack integrations
- **Logs**: CloudWatch Logs withInsights queries

### Security & Compliance

- **Least-Privilege IAM**: Role-based access with IRSA for pods
- **Network Policies**: Pod-level network segmentation
- **Security Scanning**: Automated vulnerability detection in CI
- **Audit Logging**: CloudTrail for all API calls
- **Private Registry**: ECR with image scanning enabled

### Reliability

- **Auto-Scaling**: HPA for pods, Cluster Autoscaler for nodes
- **Multi-AZ**: Cross-AZ redundancy for all stateful services
- **Backups**: Automated RDS snapshots, Terraform state backups
- **Disaster Recovery**: Documented runbooks and recovery procedures

### Cost Optimization

- **Spot Instances**: Mixed on-demand/spot node groups
- **Right-Sizing**: Resource requests/limits on all containers
- **Lifecycle Policies**: S3 object lifecycle for cost reduction
- **Autoscaling**: Scale-to-zero capabilities where applicable

---

## 📁 Project Structure

```
.
├── README.md                          # This file
├── Dockerfile                         # Multi-stage application Dockerfile
├── docs/
│   ├── PLATFORM.md                    # Platform architecture documentation
│   └── RUNBOOK.md                     # Operational runbook
├── terraform/
│   ├── backend.tf                     # S3 backend configuration
│   ├── modules/
│   │   ├── vpc/                       # VPC networking module
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── eks/                       # EKS cluster module
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── rds/                       # RDS PostgreSQL module
│   │   │   └── main.tf
│   │   ├── redis/                     # ElastiCache Redis module
│   │   │   └── main.tf
│   │   ├── s3/                        # S3 + CloudFront module
│   │   │   └── main.tf
│   │   ├── iam/                       # IAM roles and policies
│   │   │   └── main.tf
│   │   └── monitoring/                # Monitoring stack
│   │       └── main.tf
│   └── environments/
│       ├── dev/                       # Development environment
│       │   └── main.tf
│       ├── staging/                   # Staging environment
│       │   └── main.tf
│       └── prod/                      # Production environment
│           └── main.tf
├── k8s/
│   ├── base/                          # Base cluster resources
│   │   ├── namespace.yaml
│   │   └── network-policies.yaml
│   ├── apps/                          # Application deployments
│   │   └── api-gateway/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── hpa.yaml
│   │       └── ingress.yaml
│   └── monitoring/                    # Monitoring stack
│       ├── prometheus-deployment.yaml
│       ├── grafana-deployment.yaml
│       └── cert-manager.yaml
├── .github/
│   └── workflows/                     # CI/CD pipelines
│       ├── terraform-plan.yml
│       ├── terraform-apply.yml
│       ├── docker-build-push.yml
│       └── security-scan.yml
└── scripts/                           # Utility scripts
    ├── setup.sh
    └── backup.sh
```

---

## 🚀 Getting Started

### Prerequisites

- **AWS CLI** (v2.0+)
- **Terraform** (v1.5+)
- **kubectl** (v1.28+)
- **Helm** (v3.12+)
- **Docker** (v24.0+)
- **GitHub CLI** (optional)

### Quick Start

#### 1. Clone the Repository

```bash
git clone https://github.com/rajeshwarrao1253/cloud-native-devops-platform.git
cd cloud-native-devops-platform
```

#### 2. Configure AWS Credentials

```bash
aws configure
# or use SSO
aws sso login --profile dev
```

#### 3. Initialize and Apply Infrastructure

```bash
# Navigate to the environment directory
cd terraform/environments/dev

# Initialize Terraform with S3 backend
terraform init

# Plan the infrastructure
terraform plan -var="environment=dev" -out=tfplan

# Apply the infrastructure
terraform apply tfplan
```

#### 4. Configure kubectl

```bash
# Update kubeconfig for the EKS cluster
aws eks update-kubeconfig --region us-west-2 --name dev-cluster

# Verify cluster access
kubectl get nodes
```

#### 5. Deploy Applications

```bash
# Apply base resources
kubectl apply -f k8s/base/

# Deploy applications
kubectl apply -f k8s/apps/

# Deploy monitoring stack
kubectl apply -f k8s/monitoring/
```

#### 6. Access ArgoCD

```bash
# Port-forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

---

## 🔒 Security

### Security Model

This platform implements a **defense-in-depth** security strategy:

1. **Network Layer**: Private subnets, security groups, network policies
2. **Identity Layer**: IAM roles, IRSA, OIDC authentication
3. **Data Layer**: KMS encryption, TLS in transit, encrypted volumes
4. **Application Layer**: Pod security standards, RBAC, secrets management
5. **Pipeline Layer**: Security scanning, signed images, SLSA compliance

### Security Scanning

```bash
# Terraform security scanning
tfsec .

# Container image scanning
trivy image myapp:latest

# Kubernetes manifest scanning
trivy k8s --report summary k8s/
```

### Compliance

- CIS AWS Foundations Benchmark
- CIS Kubernetes Benchmark
- SOC 2 Type II ready architecture
- GDPR-compliant data handling

---

## 📊 Monitoring

### Default Dashboards

| Dashboard | Description |
|-----------|-------------|
| **Cluster Overview** | Node status, pod count, resource utilization |
| **Application Metrics** | Request rate, latency, error rate (RED metrics) |
| **Infrastructure** | CPU, memory, disk, network for all nodes |
| **Database** | RDS connections, query performance, replication lag |
| **Cost Analysis** | Resource costs by namespace and deployment |

### Alerting Rules

| Alert | Severity | Condition |
|-------|----------|-----------|
| HighCPUUsage | warning | CPU > 80% for 5m |
| HighMemoryUsage | critical | Memory > 90% for 5m |
| PodCrashLooping | critical | Pod restart count > 5 |
| NodeDiskPressure | warning | Disk usage > 85% |
| DatabaseConnectionsHigh | warning | Connections > 80% of max |

---

## 🤝 Contributing

Contributions are welcome! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Built with ❤️ for the DevOps community**

</div>
