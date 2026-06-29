# Platform Architecture Documentation

## Table of Contents

1. [Introduction](#introduction)
2. [Multi-Environment Strategy](#multi-environment-strategy)
3. [GitOps Flow](#gitops-flow)
4. [Security Model](#security-model)
5. [Disaster Recovery](#disaster-recovery)
6. [Networking Architecture](#networking-architecture)
7. [Data Management](#data-management)

---

## Introduction

The Cloud-Native DevOps Platform is designed as a production-grade infrastructure foundation that enables teams to deploy, manage, and scale containerized applications on AWS with enterprise-level security, observability, and reliability.

### Design Principles

1. **Infrastructure as Code**: All infrastructure is defined and managed through Terraform
2. **Immutability**: Infrastructure changes only through code commits and CI/CD pipelines
3. **Least Privilege**: Every component has only the permissions it needs
4. **Observability**: Every layer emits metrics, logs, and traces
5. **Resilience**: Multi-AZ deployment with automated failover

---

## Multi-Environment Strategy

### Environment Overview

We maintain three distinct environments with increasing levels of stability and control:

| Environment | Purpose | Deployment Trigger | Approval Required |
|------------|---------|-------------------|-------------------|
| **Dev** | Development, experimentation | Every push to `develop` branch | No |
| **Staging** | Integration testing, QA | Every push to `main` branch | No |
| **Production** | Live customer traffic | Manual trigger or tagged release | Yes (2 approvals) |

### Environment Isolation

Each environment is deployed to a separate AWS account to ensure:

- **Blast Radius Containment**: Issues in one environment don't affect others
- **Independent Scaling**: Each environment scales based on its own needs
- **Access Control**: Different team members have access to different environments
- **Cost Attribution**: Easy tracking of costs per environment

### Configuration Strategy

We use a combination of Terraform workspace variables and environment-specific files:

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf          # Dev-specific resource composition
│   │   ├── variables.tf     # Dev variable defaults
│   │   └── terraform.tfvars # Dev-specific values
│   ├── staging/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
```

### Promotion Flow

```
┌─────────┐     ┌──────────┐     ┌──────────┐     ┌─────────────┐
│  Local  │────▶│   Dev    │────▶│ Staging  │────▶│ Production  │
│  Dev    │     │  (AWS)   │     │  (AWS)   │     │   (AWS)     │
└─────────┘     └──────────┘     └──────────┘     └─────────────┘
                     │                 │                  │
                Auto-deploy      Auto-deploy        Manual gate
                tf plan           tf plan           tf plan
                + validate        + security scan   + 2 approvals
```

---

## GitOps Flow

### Architecture

We use **ArgoCD** as our GitOps controller, following the GitOps methodology where:

1. Git is the single source of truth for all application state
2. All changes are made through Git commits
3. Automated agents (ArgoCD) apply changes to the cluster
4. Drift detection ensures cluster state matches Git state

### GitOps Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         Git Repository                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │  App Source  │  │   K8s       │  │    Terraform Code       │ │
│  │  Code        │  │   Manifests │  │                         │ │
│  │  (main)      │  │   (k8s/)    │  │    (terraform/)         │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   ArgoCD        │
                    │   (in-cluster)  │
                    │                 │
                    │ ┌─────────────┐ │
                    │ │ Application │ │
                    │ │ Controller   │ │
                    │ └─────────────┘ │
                    │ ┌─────────────┐ │
                    │ │ Repo Server  │ │
                    │ └─────────────┘ │
                    │ ┌─────────────┐ │
                    │ │ Dex (SSO)   │ │
                    │ └─────────────┘ │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  EKS Cluster    │
                    │                 │
                    │ ┌───────────┐   │
                    │ │ Namespaces│   │
                    │ │ Services  │   │
                    │ │ Deployments│  │
                    │ └───────────┘   │
                    └─────────────────┘
```

### Application Deployment Flow

1. Developer pushes application code to Git
2. GitHub Actions builds Docker image and pushes to ECR
3. ArgoCD detects new image tag in Git
4. ArgoCD syncs the new manifest to the cluster
5. Kubernetes performs rolling update
6. ArgoCD verifies health and sync status

### ArgoCD Configuration

```yaml
# Example Application manifest
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api-gateway
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/rajeshwarrao1253/cloud-native-devops-platform
    targetRevision: HEAD
    path: k8s/apps/api-gateway
  destination:
    server: https://kubernetes.default.svc
    namespace: apps
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## Security Model

### Defense in Depth

Our security model implements multiple layers of protection:

```
┌─────────────────────────────────────────────────────────────┐
│                    PERIMETER SECURITY                        │
│  • AWS Shield (DDoS protection)                             │
│  • AWS WAF (Web Application Firewall)                       │
│  • CloudFront with geo-restrictions                         │
├─────────────────────────────────────────────────────────────┤
│                    NETWORK SECURITY                          │
│  • VPC Isolation                                            │
│  • Private subnets for workloads                            │
│  • Security groups with least-privilege rules               │
│  • Network policies for pod-to-pod traffic                  │
├─────────────────────────────────────────────────────────────┤
│                    IDENTITY & ACCESS                         │
│  • IAM roles with least-privilege policies                  │
│  • IRSA for pod-level AWS access                            │
│  • OIDC authentication for cluster access                   │
│  • RBAC for Kubernetes resource access                      │
├─────────────────────────────────────────────────────────────┤
│                    DATA SECURITY                             │
│  • KMS encryption for all data at rest                      │
│  • TLS 1.3 for all data in transit                          │
│  • Secrets management with AWS Secrets Manager              │
│  • Automated secret rotation                                │
├─────────────────────────────────────────────────────────────┤
│                    APPLICATION SECURITY                      │
│  • Pod Security Standards (restricted)                      │
│  • Read-only root filesystem                                │
│  • Non-root container execution                             │
│  • Security scanning in CI/CD pipeline                      │
└─────────────────────────────────────────────────────────────┘
```

### IAM Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      AWS Account                                │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Admin Role  │  │  Dev Role    │  │  CI/CD Role  │          │
│  │  (Full Access)│  │(Limited)     │  │ (Automated)  │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                  │
│         └──────────────────┼──────────────────┘                  │
│                            ▼                                    │
│                   ┌─────────────────┐                           │
│                   │   IAM Policies   │                           │
│                   │  (Least Privilege)│                           │
│                   └────────┬────────┘                           │
│                            │                                    │
│         ┌──────────────────┼──────────────────┐                │
│         ▼                  ▼                  ▼                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   EKS Role    │  │   RDS Role   │  │   S3 Role    │          │
│  │  (Cluster)    │  │  (Database)  │  │  (Storage)   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Kubernetes RBAC                             │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────────────────────┐ │    │
│  │  │ Cluster │  │  NS     │  │       Service           │ │    │
│  │  │ Admin   │  │  Admin  │  │       Accounts          │ │    │
│  │  └─────────┘  └─────────┘  └─────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Network Security

1. **VPC Flow Logs**: All network traffic is logged for analysis
2. **Security Groups**: Stateful firewalls with minimal required rules
3. **Network Policies**: Kubernetes-native pod-to-pod traffic control
4. **Private Subnets**: Workloads cannot be accessed directly from internet
5. **NAT Gateways**: Controlled outbound internet access

---

## Disaster Recovery

### RTO and RPO Targets

| Environment | RTO (Recovery Time Objective) | RPO (Recovery Point Objective) |
|------------|------------------------------|--------------------------------|
| Dev | 4 hours | 24 hours |
| Staging | 2 hours | 12 hours |
| Production | 1 hour | 5 minutes |

### Backup Strategy

#### Infrastructure State

- **Terraform State**: Stored in S3 with versioning enabled
- **State Locking**: DynamoDB table for state locking
- **Cross-Region Replication**: State bucket replicated to secondary region

#### Application Data

- **RDS Automated Backups**: Daily snapshots with 35-day retention
- **RDS Cross-Region Snapshots**: Weekly snapshots to disaster recovery region
- **S3 Versioning**: All objects versioned with MFA delete protection
- **ElastiCache Snapshots**: Daily automated snapshots

#### Kubernetes State

- **etcd Backups**: Automated daily backups via Velero
- **Persistent Volumes**: Snapshots via EBS CSI driver
- **Secrets**: Stored in AWS Secrets Manager with rotation

### Disaster Recovery Procedures

#### Scenario 1: Availability Zone Failure

1. **Detection**: CloudWatch alarms detect AZ failure
2. **Impact**: Multi-AZ services automatically failover
3. **Action**: No manual action required for Multi-AZ services
4. **Verification**: Confirm service health in remaining AZs

#### Scenario 2: Region Failure

1. **Detection**: Global health checks fail
2. **Notification**: PagerDuty alerts to on-call engineer
3. **Decision**: Activate disaster recovery procedures
4. **Action**:
   - Update Route53 DNS to point to DR region
   - Restore RDS from cross-region snapshot
   - Scale up EKS cluster in DR region
   - Verify application functionality
5. **Recovery Time**: ~1 hour for full service restoration

#### Scenario 3: Data Corruption

1. **Detection**: Data integrity checks fail
2. **Isolation**: Stop write operations to affected resources
3. **Assessment**: Determine extent of corruption
4. **Recovery**:
   - Restore RDS from point-in-time backup
   - Restore S3 objects from previous versions
   - Restore ElastiCache from snapshot
5. **Verification**: Validate data integrity after restoration

### Runbook References

For detailed operational procedures, see [RUNBOOK.md](RUNBOOK.md).

---

## Networking Architecture

### VPC Design

```
┌─────────────────────────────────────────────────────────────────────┐
│                              VPC (10.0.0.0/16)                      │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                        Availability Zone A                       │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │ │
│  │  │  Public-A    │  │  Private-A   │  │  Database-A  │          │ │
│  │  │  10.0.1.0/24 │  │  10.0.4.0/24 │  │  10.0.7.0/24 │          │ │
│  │  │  (ALB, NAT)  │  │  (EKS, Apps) │  │  (RDS, Redis)│          │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘          │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                        Availability Zone B                       │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │ │
│  │  │  Public-B    │  │  Private-B   │  │  Database-B  │          │ │
│  │  │  10.0.2.0/24 │  │  10.0.5.0/24 │  │  10.0.8.0/24 │          │ │
│  │  │  (ALB, NAT)  │  │  (EKS, Apps) │  │  (RDS, Redis)│          │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘          │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                        Availability Zone C                       │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │ │
│  │  │  Public-C    │  │  Private-C   │  │  Database-C  │          │ │
│  │  │  10.0.3.0/24 │  │  10.0.6.0/24 │  │  10.0.9.0/24 │          │ │
│  │  │  (ALB, NAT)  │  │  (EKS, Apps) │  │  (RDS, Redis)│          │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘          │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  Internet Gateway ──▶ NAT Gateways ──▶ Private Subnets              │
│       │                     │                    │                   │
│       ▼                     ▼                    ▼                   │
│  ┌──────────┐       ┌──────────┐       ┌──────────────┐             │
│  │  WAF     │       │  Route   │       │  VPC Endpoints│             │
│  │  Shield  │       │  Tables  │       │  (S3, ECR)   │             │
│  └──────────┘       └──────────┘       └──────────────┘             │
└─────────────────────────────────────────────────────────────────────┘
```

### Network Flow

1. **Inbound**: CloudFront → WAF → ALB (public subnet) → Pods (private subnet)
2. **Outbound**: Pods (private) → NAT Gateway (public) → Internet
3. **East-West**: Pod-to-pod traffic controlled by Network Policies
4. **Data**: Pods (private) → RDS/Redis (database subnets) via security groups

---

## Data Management

### Data Classification

| Classification | Description | Encryption | Access Control |
|---------------|-------------|------------|----------------|
| **Public** | Non-sensitive, publicly available | TLS in transit | Public read |
| **Internal** | Business data, not customer-facing | AES-256 at rest, TLS | Authenticated users |
| **Confidential** | Customer data, PII | AES-256 at rest, TLS 1.3 | Role-based access |
| **Restricted** | Financial, health data | AES-256 at rest, TLS 1.3, field-level | Strict need-to-know |

### Data Retention

| Data Type | Retention Period | Deletion Method |
|-----------|-----------------|-----------------|
| Application logs | 90 days | Automated |
| Audit logs | 7 years | Manual after compliance period |
| Database backups | 35 days | Automated |
| Cross-region snapshots | 1 year | Manual |
| Terraform state | Indefinite (versioned) | Manual |

### Data Flow

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  Users   │────▶│ CloudFront│────▶│   ALB    │────▶│   EKS    │
│          │     │   CDN    │     │          │     │   Pods   │
└──────────┘     └──────────┘     └──────────┘     └────┬─────┘
                                                         │
                              ┌──────────────────────────┼──────────────────────────┐
                              │                          │                          │
                              ▼                          ▼                          ▼
                        ┌──────────┐              ┌──────────┐              ┌──────────┐
                        │   RDS    │              │  Redis   │              │    S3    │
                        │PostgreSQL│              │  Cache   │              │  Assets  │
                        │          │              │          │              │          │
                        │  Multi-AZ│              │  Cluster │              │ Versioned│
                        │Encrypted │              │Encrypted │              │Encrypted │
                        └──────────┘              └──────────┘              └──────────┘
```

---

## Operational Excellence

### Key Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Infrastructure Deployment Time | < 15 minutes | Terraform apply duration |
| Application Deployment Time | < 5 minutes | ArgoCD sync duration |
| Mean Time to Detection (MTTD) | < 2 minutes | Alertmanager alert time |
| Mean Time to Resolution (MTTR) | < 30 minutes | Incident response time |
| Change Failure Rate | < 5% | Failed deployments / total deployments |
| Deployment Frequency | Multiple per day | Number of production deployments |

### Continuous Improvement

1. **Weekly Reviews**: Review incidents, identify patterns
2. **Monthly Audits**: Security and cost optimization audits
3. **Quarterly DR Drills**: Test disaster recovery procedures
4. **Annual Penetration Testing**: Third-party security assessment
