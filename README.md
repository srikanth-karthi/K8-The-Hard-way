# Kubernetes The Hard Way - Documentation

This repository contains comprehensive documentation for setting up Kubernetes from scratch using "The Hard Way" approach. This hands-on tutorial covers the complete setup process from provisioning compute resources to understanding deep networking concepts.

## Documentation Structure

The documentation is organized in three progressive modules:

### 📋 01. Provisioning Compute Resources
**File:** [`01-provisioning-compute-resources.md`](01-provisioning-compute-resources.md)

Complete guide for setting up the foundational infrastructure for a Kubernetes cluster.

**What you'll learn:**
- Machine database schema and configuration management
- SSH key generation, distribution, and security setup
- Hostname and FQDN configuration across cluster nodes
- Host lookup table creation and distribution
- Network connectivity verification procedures

**Architecture covered:**
- 3-node cluster setup (1 control plane + 2 worker nodes)
- Jumpbox orchestration approach
- Inter-node communication setup

### 🔧 02. Kubernetes High Availability & Leader Election
**File:** [`02-kubernetes-high-availability-leader-election.md`](02-kubernetes-high-availability-leader-election.md)

Deep dive into Kubernetes control plane high availability mechanisms and leader election patterns.

**What you'll learn:**
- Multi-master cluster topology with Network Load Balancer
- etcd Raft consensus protocol and leader election
- Controller Manager and Scheduler leader election using Lease API
- API Server active-active configuration behind load balancer
- Failover scenarios and recovery timelines (~15 seconds)

**Key verification commands:**
```bash
# Check etcd cluster status
etcdctl endpoint status --endpoints=$ENDPOINTS --write-out=table

# Verify controller manager leader
kubectl get lease kube-controller-manager -n kube-system -o yaml | grep holderIdentity

# Check API server health
kubectl --server=https://<master-ip>:6443 get --raw /healthz
```

### 🌐 03. Container Runtime & Networking Deep Dive  
**File:** [`03-containerd-cni-networking-deep-dive.md`](03-containerd-cni-networking-deep-dive.md)

Comprehensive explanation of container runtime architecture and Pod networking lifecycle.

**What you'll learn:**
- containerd architecture and CRI (Container Runtime Interface) integration
- CNI (Container Network Interface) plugin chain execution
- Linux IP routing for cross-node Pod communication
- Complete Pod lifecycle from API submission to network teardown
- Pause container purpose and network namespace management

**Key components covered:**
- **containerd**: Container runtime with gRPC API, snapshotter, and CNI integration
- **CNI plugins**: Bridge, loopback, and host-local IPAM configuration
- **Linux routing**: Manual route setup for Pod subnet connectivity
- **kube-proxy**: Service proxying and iptables rule management

## System Architecture Overview

```
┌───────────────────────────┐
│   API Server LoadBalancer │
│   (port 6443, /healthz)   │
└──────────▲────────────────┘
           │
  ┌────────┴────────┬───────────────┐
  │  Master 0       │   Master 1     │
  │ ┌─────────┐     │ ┌─────────┐   │
  │ │etcd     │     │ │etcd     │   │
  │ │(raft)   │ ... │ │(raft)   │   │
  │ └─────────┘     │ └─────────┘   │
  └─────────────────┴───────────────┘
           │
    Worker Nodes
  - kubelet & kube-proxy
  - CNI networking
  - containerd runtime
```

## Prerequisites

Before starting, ensure you have:

- **Infrastructure**: Access to 3+ machines (physical or virtual)
- **Access**: Root or sudo privileges on all machines
- **Networking**: SSH connectivity between all machines
- **Knowledge**: Basic understanding of Linux networking and containers

## Getting Started

Follow the documentation in numerical order for best learning experience:

1. **Start with infrastructure**: Set up your compute resources and basic networking
2. **Configure high availability**: Understand and implement HA patterns
3. **Deep dive networking**: Learn the internals of container networking

Each document includes:
- ✅ Step-by-step instructions with commands
- 🔍 Verification procedures and expected outputs  
- 🚨 Troubleshooting guidance
- 📖 Conceptual explanations of underlying mechanisms

## Important Security Notice

⚠️ **Lab Environment Only**: The SSH and networking configurations described in this tutorial are designed for learning environments. Production deployments should implement:

- Certificate-based authentication instead of password/key-based SSH
- Network segmentation and firewall rules
- Encrypted etcd communication
- RBAC (Role-Based Access Control) policies
- Pod Security Standards

## Learning Outcomes

After completing this tutorial, you will have:

- Deep understanding of Kubernetes component interactions
- Hands-on experience with container runtime internals
- Knowledge of networking fundamentals in Kubernetes
- Practical skills in cluster troubleshooting and maintenance
- Foundation for advanced Kubernetes operations and security

## Additional Resources

- [Official Kubernetes Documentation](https://kubernetes.io/docs/)
- [containerd Documentation](https://containerd.io/docs/)
- [CNI Specification](https://github.com/containernetworking/cni)
- [etcd Documentation](https://etcd.io/docs/)