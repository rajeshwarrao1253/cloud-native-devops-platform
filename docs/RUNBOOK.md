# Operational Runbook

## Table of Contents

1. [Introduction](#introduction)
2. [Common Issues](#common-issues)
3. [Scaling Procedures](#scaling-procedures)
4. [Rollback Procedures](#rollback-procedures)
5. [Incident Response](#incident-response)
6. [Maintenance Windows](#maintenance-windows)
7. [Contact Information](#contact-information)

---

## Introduction

This runbook provides operational procedures for the Cloud-Native DevOps Platform. It is intended for SREs, DevOps engineers, and on-call personnel who need to respond to incidents, perform maintenance, or troubleshoot issues.

### Severity Levels

| Level | Description | Response Time | Examples |
|-------|-------------|---------------|----------|
| **SEV-1** | Critical - Service down | 15 minutes | Production outage, data loss |
| **SEV-2** | High - Major impact | 30 minutes | Performance degradation, partial outage |
| **SEV-3** | Medium - Minor impact | 2 hours | Non-critical feature unavailable |
| **SEV-4** | Low - No immediate impact | 1 business day | Security patches, optimizations |

---

## Common Issues

### Issue: Pod Stuck in Pending State

**Symptoms**: Pod remains in `Pending` state, not scheduled on any node.

**Diagnosis**:
```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check node resources
kubectl top nodes

# Check cluster autoscaler logs
kubectl logs -n kube-system deployment/cluster-autoscaler
```

**Common Causes & Solutions**:

1. **Insufficient Resources**
   ```bash
   # Check resource requests vs available
   kubectl describe nodes | grep -A 5 "Allocated resources"
   
   # Solution: Scale node group or reduce resource requests
   kubectl patch deployment <deployment-name> -n <namespace> \
     -p '{"spec":{"template":{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"100m","memory":"128Mi"}}}]}}}}'
   ```

2. **Node Group at Capacity**
   ```bash
   # Check cluster autoscaler status
   kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml
   
   # Manual scale if autoscaler is stuck
   aws eks update-nodegroup-config \
     --cluster-name <cluster-name> \
     --nodegroup-name <nodegroup-name> \
     --scaling-config minSize=3,maxSize=10,desiredSize=5
   ```

3. **PVC Not Bound**
   ```bash
   # Check PVC status
   kubectl get pvc -n <namespace>
   
   # Check storage class
   kubectl get storageclass
   
   # If EBS CSI driver issue, restart driver
   kubectl rollout restart deployment ebs-csi-controller -n kube-system
   ```

### Issue: High Memory Usage

**Symptoms**: Nodes or pods showing high memory utilization, OOMKilled events.

**Diagnosis**:
```bash
# Top memory-consuming pods
kubectl top pods --all-namespaces --sort-by=memory

# Check for memory leaks
kubectl logs <pod-name> -n <namespace> | grep -i "out of memory\|oom"

# Node memory pressure
kubectl describe nodes | grep -A 10 "MemoryPressure"
```

**Solutions**:

1. **Pod Level - Set Memory Limits**
   ```bash
   # Edit deployment to add/set memory limits
   kubectl set resources deployment <deployment-name> \
     -n <namespace> \
     --limits=memory=512Mi \
     --requests=memory=256Mi
   ```

2. **Node Level - Drain and Replace**
   ```bash
   # Cordon the node
   kubectl cordon <node-name>
   
   # Drain pods to other nodes
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
   
   # Terminate node via AWS console or CLI
   aws ec2 terminate-instances --instance-ids <instance-id>
   ```

3. **Cluster Level - Scale Up**
   ```bash
   # Increase node group size
   eksctl scale nodegroup \
     --cluster <cluster-name> \
     --name <nodegroup-name> \
     --nodes 5 \
     --nodes-min 3 \
     --nodes-max 10
   ```

### Issue: Database Connection Pool Exhausted

**Symptoms**: Application errors "too many connections", high connection count in RDS.

**Diagnosis**:
```bash
# Check current connections
aws rds describe-db-clusters \
  --db-cluster-identifier <cluster-id> \
  --query 'DBClusters[0].DatabaseConnections'

# Check CloudWatch metric
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=<cluster-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average
```

**Solutions**:

1. **Immediate - Increase Max Connections**
   ```bash
   # Modify parameter group (requires reboot)
   aws rds modify-db-parameter-group \
     --db-parameter-group-name <param-group> \
     --parameters ParameterName=max_connections,ParameterValue=500,ApplyMethod=pending-reboot
     
   # Reboot instance
   aws rds reboot-db-instance --db-instance-identifier <instance-id>
   ```

2. **Application - Connection Pool Tuning**
   ```yaml
   # Update application config
   DB_POOL_SIZE: 20
   DB_POOL_TIMEOUT: 5000
   DB_POOL_MAX_OVERFLOW: 10
   DB_POOL_RECYCLE: 3600
   ```

3. **Long-term - Read Replicas**
   ```bash
   # Create read replica
   aws rds create-db-instance-read-replica \
     --db-instance-identifier <replica-id> \
     --source-db-instance-identifier <source-id>
   ```

### Issue: SSL Certificate Expired

**Symptoms**: Users report SSL errors, cert-manager showing failed certificate requests.

**Diagnosis**:
```bash
# Check certificate status
kubectl get certificates -A

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate details
kubectl describe certificate <cert-name> -n <namespace>

# Manual SSL check
openssl s_client -connect <domain>:443 -servername <domain> 2>/dev/null | openssl x509 -noout -dates
```

**Solutions**:

1. **Force Certificate Renewal**
   ```bash
   # Delete the secret to force re-issuance
   kubectl delete secret <tls-secret-name> -n <namespace>
   
   # Trigger manual renewal
   kubectl cert-manager renew <certificate-name> -n <namespace>
   ```

2. **Check cert-manager Configuration**
   ```bash
   # Verify ClusterIssuer exists
   kubectl get clusterissuers
   
   # Verify DNS challenge is working
   kubectl describe challenges -A
   ```

### Issue: ArgoCD Application Out of Sync

**Symptoms**: ArgoCD shows application as `OutOfSync`, automated sync not working.

**Diagnosis**:
```bash
# Check application status
argocd app get <app-name>

# Check sync status
kubectl get application <app-name> -n argocd -o yaml

# Check app controller logs
kubectl logs -n argocd deployment/argocd-application-controller
```

**Solutions**:

1. **Manual Sync**
   ```bash
   argocd app sync <app-name>
   ```

2. **Hard Refresh**
   ```bash
   argocd app get <app-name> --hard-refresh
   ```

3. **Check for Resource Conflicts**
   ```bash
   # Check for resource differences
   argocd app diff <app-name>
   
   # If resources were manually modified, restore them
   argocd app sync <app-name> --prune
   ```

---

## Scaling Procedures

### Horizontal Pod Scaling (HPA)

**When to Use**: Increased traffic, high CPU/memory utilization.

```bash
# Check current HPA status
kubectl get hpa -n <namespace>

# Manually scale deployment (temporary)
kubectl scale deployment <deployment-name> --replicas=10 -n <namespace>

# Update HPA limits permanently
kubectl patch hpa <hpa-name> -n <namespace> \
  -p '{"spec":{"maxReplicas":20,"metrics":[{"type":"Resource","resource":{"name":"cpu","target":{"type":"Utilization","averageUtilization":70}}}]}}'
```

### Cluster Node Scaling

**When to Use**: HPA cannot scale further due to insufficient cluster capacity.

```bash
# Check current node utilization
kubectl top nodes

# Check if cluster autoscaler is working
kubectl get events -n kube-system | grep -i autoscaler

# Manual node group scaling
aws eks update-nodegroup-config \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --scaling-config desiredSize=8

# Using eksctl
eksctl scale nodegroup \
  --cluster <cluster-name> \
  --name <nodegroup-name> \
  --nodes 8
```

### Database Scaling

#### Vertical Scaling (Instance Size)

```bash
# Scale RDS instance class
aws rds modify-db-instance \
  --db-instance-identifier <instance-id> \
  --db-instance-class db.r5.2xlarge \
  --apply-immediately

# Monitor scaling progress
aws rds describe-db-instances \
  --db-instance-identifier <instance-id> \
  --query 'DBInstances[0].[DBInstanceStatus,PendingModifiedValues]'
```

#### Horizontal Scaling (Read Replicas)

```bash
# Create read replica
aws rds create-db-instance-read-replica \
  --db-instance-identifier <replica-name> \
  --source-db-instance-identifier <source-name>

# Promote read replica (for write scaling or failover)
aws rds promote-read-replica \
  --db-instance-identifier <replica-name>
```

### Cache Scaling

```bash
# Scale Redis cluster
aws elasticache modify-replication-group \
  --replication-group-id <redis-id> \
  --cache-node-type cache.r5.large \
  --apply-immediately

# Add shards (for cluster mode)
aws elasticache modify-replication-group-shard-configuration \
  --replication-group-id <redis-id> \
  --node-group-count 4 \
  --apply-immediately
```

---

## Rollback Procedures

### Application Rollback

#### Kubernetes Deployment Rollback

```bash
# View rollout history
kubectl rollout history deployment/<deployment-name> -n <namespace>

# Rollback to previous revision
kubectl rollout undo deployment/<deployment-name> -n <namespace>

# Rollback to specific revision
kubectl rollout undo deployment/<deployment-name> -n <namespace> --to-revision=2

# Verify rollback
kubectl rollout status deployment/<deployment-name> -n <namespace>
```

#### ArgoCD Application Rollback

```bash
# Sync to specific Git commit
argocd app sync <app-name> --revision <commit-sha>

# Or use the UI to select a previous commit
# Access ArgoCD UI: argocd.domain.com
```

### Terraform Rollback

```bash
# View Terraform state history
terraform state list

# Rollback to previous state version (stored in S3)
# Navigate to S3 bucket and restore previous state version

# Or taint and recreate specific resources
terraform taint <resource-address>
terraform apply

# Emergency: Destroy and recreate specific resources
terraform destroy -target=<resource-address>
terraform apply
```

### Database Rollback

#### Point-in-Time Recovery

```bash
# Restore to a specific point in time
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier <source-cluster> \
  --restore-to-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --db-cluster-identifier <restored-cluster>
```

#### Snapshot Restore

```bash
# List available snapshots
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier <cluster-id>

# Restore from snapshot
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier <new-cluster-id> \
  --snapshot-identifier <snapshot-id> \
  --engine aurora-postgresql
```

---

## Incident Response

### Incident Response Process

```
┌─────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ Detect  │────▶│ Triage   │────▶│ Respond  │────▶│ Resolve  │────▶│ Review   │
│         │     │          │     │          │     │          │     │          │
│ Alert   │     │ Assess   │     │ Mitigate │     │ Fix      │     │ Document │
│ received│     │ severity │     │ impact   │     │ root     │     │ lessons  │
│         │     │ Identify │     │          │     │ cause    │     │ learned  │
│         │     │ scope    │     │          │     │          │     │          │
└─────────┘     └──────────┘     └──────────┘     └──────────┘     └──────────┘
```

### Incident Response Checklist

#### Initial Response (0-5 minutes)

- [ ] Acknowledge the alert in PagerDuty
- [ ] Join incident war room (Slack #incidents)
- [ ] Assess severity and impact
- [ ] Identify affected services and users
- [ ] Determine if rollback is needed

#### Investigation (5-30 minutes)

- [ ] Check recent deployments
- [ ] Review application and infrastructure logs
- [ ] Check CloudWatch dashboards
- [ ] Query Prometheus metrics
- [ ] Identify error patterns
- [ ] Determine root cause

#### Resolution (30-60 minutes)

- [ ] Apply fix or execute rollback
- [ ] Verify service restoration
- [ ] Monitor for stability
- [ ] Communicate status to stakeholders

#### Post-Incident

- [ ] Write post-mortem document
- [ ] Schedule blameless post-mortem meeting
- [ ] Create action items for prevention
- [ ] Update runbooks with new learnings

### Communication Templates

#### Incident Started

```
🚨 **Incident Alert** 🚨

**Severity**: [SEV-1/SEV-2/SEV-3]
**Service**: [Affected service]
**Impact**: [Description of user impact]
**Started**: [Timestamp]
**Status**: Investigating

We are currently investigating an issue affecting [service]. 
We will provide updates every 15 minutes.
```

#### Status Update

```
📋 **Incident Update** [XX minutes in]

**Service**: [Affected service]
**Status**: [Investigating/Identified/Monitoring/Resolved]
**Update**: [Brief description of progress]

Next update in 15 minutes or upon significant change.
```

#### Incident Resolved

```
✅ **Incident Resolved**

**Service**: [Affected service]
**Duration**: [Total duration]
**Resolution**: [Brief description of fix]

Services are fully operational. A post-mortem will be shared within 24 hours.
```

---

## Maintenance Windows

### Regular Maintenance Schedule

| Maintenance Task | Frequency | Window | Owner |
|-----------------|-----------|--------|-------|
| Security patches | Weekly | Tuesday 2-4 AM UTC | SRE Team |
| Node OS updates | Bi-weekly | Thursday 2-4 AM UTC | SRE Team |
| Certificate renewal | Monthly | First Monday 10 AM UTC | SRE Team |
| Database maintenance | Monthly | Second Sunday 2-6 AM UTC | DBA Team |
| Cost optimization review | Monthly | Last Friday 2 PM UTC | FinOps Team |
| Disaster recovery drill | Quarterly | Scheduled | SRE Team |
| Penetration testing | Annually | Scheduled | Security Team |

### Pre-Maintenance Checklist

- [ ] Announce maintenance window 48 hours in advance
- [ ] Verify backup completion
- [ ] Confirm maintenance procedures are documented
- [ ] Have rollback plan ready
- [ ] Verify on-call engineer availability
- [ ] Prepare monitoring dashboards

### Post-Maintenance Checklist

- [ ] Verify all services are healthy
- [ ] Run smoke tests
- [ ] Monitor for 2 hours post-maintenance
- [ ] Update maintenance log
- [ ] Communicate completion to stakeholders

---

## Emergency Contacts

| Role | Contact | Escalation |
|------|---------|------------|
| **Primary On-Call** | PagerDuty Rotation | Auto-escalates after 15 min |
| **SRE Lead** | sre-lead@company.com | +1-XXX-XXX-XXXX |
| **Platform Engineering** | platform-team@company.com | Slack #platform-support |
| **Security Team** | security@company.com | +1-XXX-XXX-XXXX |
| **AWS Support** | Business/Enterprise | AWS Console |

### Escalation Path

```
Level 1: On-Call Engineer (15 min)
    ↓
Level 2: SRE Team Lead (15 min)
    ↓
Level 3: Engineering Manager (30 min)
    ↓
Level 4: Director of Engineering (1 hour)
    ↓
Level 5: VP Engineering / CTO
```

---

## Useful Commands Reference

### AWS

```bash
# EKS
aws eks list-clusters --region us-west-2
aws eks describe-cluster --name <cluster-name>
aws eks update-kubeconfig --name <cluster-name>

# RDS
aws rds describe-db-clusters
aws rds describe-db-instances
aws rds describe-db-cluster-snapshots

# ElastiCache
aws elasticache describe-replication-groups
aws elasticache describe-cache-clusters

# EC2
aws ec2 describe-instances --filters Name=tag:Environment,Values=prod
aws ec2 describe-vpcs
```

### Kubernetes

```bash
# Pod management
kubectl get pods -A
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --tail=100 -f
kubectl exec -it <pod> -n <ns> -- /bin/sh

# Node management
kubectl get nodes -o wide
kubectl describe node <node>
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets

# Network
kubectl get svc -A
kubectl get ingress -A
kubectl get networkpolicies -A

# Storage
kubectl get pvc -A
kubectl get pv

# Events
kubectl get events --sort-by='.lastTimestamp' | tail -50
```

### Terraform

```bash
# State management
terraform state list
terraform state show <resource>
terraform state pull > terraform.tfstate

# Plan and apply
terraform plan -out=tfplan
terraform apply tfplan
terraform destroy

# Workspaces
terraform workspace list
terraform workspace select <env>
terraform workspace new <env>
```

---

*Last Updated: $(date)*
*Version: 1.0*
