# Kubernetes High Availability & Leader Election

This document outlines how Kubernetes components achieve high availability (HA) and perform leader election. It covers:

* Cluster topology overview
* etcd Raft leader election and sync
* Controller Manager leader election (Lease API)
* Scheduler leader election (Lease API)
* API Server active–active with Network Load Balancer (NLB)
* Commands to verify status
* Common fail‑over scenarios and timelines

---

## 1. Cluster Topology

Your control plane consists of multiple masters behind an NLB, and an etcd cluster spread across those masters. Worker nodes connect to the API servers via the NLB. Below is an ASCII diagram and step‑by‑step flow:

```
                   ┌───────────────────────────┐
                   │   API Server LoadBalancer │
                   │   (port 6443, /healthz)   │
                   └──────────▲────────────────┘
                              │
     ┌──────────────┬─────────┴─────────┬───────────────┐
     │  Master 0    │   Master 1        │   Master N     │
     │ (10.240.0.70)│ (10.240.0.71)     │ (...:6443)     │
     │ ┌─────────┐  │ ┌─────────┐       │ ┌─────────┐   │
     │ │etcd     │  │ │etcd     │       │ │etcd     │   │
     │ │(raft)   │  │ │(raft)   │  ...  │ │(raft)   │   │
     │ └─────────┘  │ └─────────┘       │ └─────────┘   │
     └───┬──────┬───┴───┬───────────────┴───┬───────────┘
         │      │          │                  
         ▼      ▼          ▼                  
    Controllers & Scheduler Leaders (Lease API)

Worker Nodes (e.g., node-0, node-1)
- Run kubelet & kube-proxy
- Communicate HTTPS -> LoadBalancer on port 6443
- CNI networking for pods
```

**Flow Explanation:**

1. **Client requests** hit the NLB VIP on port 6443 and are routed to one of the active `kube-apiserver` instances.
2. **Each API server** writes data to the etcd cluster (raft group) and reads from it.
3. **etcd** elects one leader (for writes) and replicates to followers automatically.
4. **Controller-Manager** and **Scheduler** on each master compete for a small **Lease** in etcd:

   * Only the Lease **holder** actively manages resources.
   * Fallback occurs within \~15s if the leader stops renewing.
5. **Workers** fetch their desired state (pods, config) via calls to the API servers and report status back.

---

## 2. etcd Raft Leader Election & Sync

### How it works

* etcd uses the Raft protocol among its members.
* One member is elected **leader**; others are **followers**.
* Leader handles writes; followers replicate entries.
* On leader failure, a new election occurs automatically.

### Verify status (no TLS)

```bash
export ETCDCTL_API=3
ENDPOINTS="http://10.240.0.70:2379,http://10.240.0.71:2379"
etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status \
  --write-out=table
```

Look for `IS LEADER=true`, and matching `RAFT INDEX` on followers.

### Verify members list

```bash
etcdctl --endpoints=$ENDPOINTS member list
```

---

## 3. Controller-Manager Leader Election (Lease API)

### Mechanism

* Each controller-manager has `--leader-elect=true`.
* They compete to acquire a **Lease** object named `kube-controller-manager` in the `kube-system` namespace.
* The holder writes its identity and renews periodically (default TTL 15s).
* Standbys watch; on TTL expiry, a standby acquires the Lease.

### Check current leader

```bash
kubectl get lease kube-controller-manager -n kube-system -o yaml \
  | grep holderIdentity
```

---

## 4. Scheduler Leader Election (Lease API)

Same pattern as controller-manager, using Lease named `kube-scheduler`:

```bash
kubectl get lease kube-scheduler -n kube-system -o yaml \
  | grep holderIdentity
```

---

### Under the hood: how leader election works

The scheduler uses the built-in leader-election library (in `client-go`) and the `Lease` API in the `coordination.k8s.io` group to ensure exactly one active scheduler:

1. **Lease Object in etcd**
   A small object called a `Lease` (named `kube-scheduler` in the `kube-system` namespace) is stored in etcd.
   That Lease holds fields like `holderIdentity`, `leaseDurationSeconds`, and a timestamp `renewTime`.

2. **Candidates Compete**
   Each `kube-scheduler` process (on `server-0`, `server-1`, etc.) starts up with the flag `--leader-elect=true`.
   They all try to **Acquire** the Lease by doing a Kubernetes API `PATCH` or `Create` on that Lease resource.

3. **One Wins—Becomes Leader**
   The first to successfully write the Lease with its own identity (`holderIdentity`) becomes the **leader**.
   In your case, that was `server-0` (you saw `holderIdentity: server-0_…`).

4. **Periodic Renewal**
   The leader process must call `Renew()` on the same Lease within its `leaseDurationSeconds` (default 15s).
   Each renewal is another API call that updates `renewTime`.

5. **Standbys Watch**
   All non-leaders keep watching that Lease via a `LIST`+`WATCH` on the Kubernetes API.
   They note `renewTime`; as long as it keeps moving forward, they stay passive.

6. **Fail-over on Stop or Crash**
   If the leader stops renewing (because you `systemctl stop kube-scheduler`), after \~15s the Lease expires.
   Standby schedulers detect the expiration (missing renew), then one of them calls **Acquire()** to overwrite the Lease.
   That one becomes the new leader—scheduling resumes immediately under the new process.

7. **Why etcd & API-Server Are Involved**
   Every Lease operation (`Create`, `Update`, `Watch`) goes through the `kube-apiserver`, which stores it in etcd.
   That gives you strong consistency and automatic fail-over without any extra orchestration.

---

## 5. API Server Active–Active behind NLB

* All API servers run with identical flags (same etcd endpoints, service CIDRs).
* A Network Load Balancer (NLB) health‑checks `/healthz` on port 6443 and distributes traffic.
* Clients use the VIP or DNS name; no single “primary” API server exists.

### Verify health endpoints

```bash
kubectl --server=https://10.240.0.70:6443 get --raw /healthz
kubectl --server=https://10.240.0.71:6443 get --raw /healthz
```

---

## 6. Commands Summary

| Component                 | Check Command                                                         |
| ------------------------- | --------------------------------------------------------------------- |
| etcd Leader & Sync        | `etcdctl endpoint status --endpoints=$ENDPOINTS --write-out=table`    |
| Controller-Manager Leader | \`kubectl get lease kube-controller-manager -n kube-system -o yaml \\ |
| grep holderIdentity\`     |                                                                       |
| Scheduler Leader          | \`kubectl get lease kube-scheduler -n kube-system -o yaml \\          |
| grep holderIdentity\`     |                                                                       |
| API Server Health         | `kubectl --server=https://<master-ip>:6443 get --raw /healthz`        |

---

## 7. Fail‑over Timeline Example

```text
# On server-0
t=0s:  Acquire Lease → leader
t=10s: Renew Lease
t=20s: server-0 crash → no renew
t=35s: Lease TTL (15s) expires
t=35s+: server-1 acquires Lease → new leader
# Scheduling resumes on server-1 within ~15s
```

---

*End of document*
