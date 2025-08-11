

# **CoreDNS DNS Resolution Intermittency – Incident Report & Resolution Guide**

## **1. Executive Summary**

A Kubernetes cluster running **CoreDNS** in IPVS mode experienced **intermittent DNS resolution failures**. Requests to the cluster DNS VIP (`10.32.0.10`) succeeded sporadically — roughly 50% of queries timed out, impacting service discovery for workloads.

Root cause was traced to **node-0** having a mismatch in packet filtering backend (iptables-nft vs iptables-legacy) causing **inconsistent kube-proxy IPVS rules** and NAT table behavior. This prevented kube-proxy from correctly routing traffic to CoreDNS pods under certain conditions.

---

## **2. Timeline**

| Time (IST) | Event                                                                                           |
| ---------- | ----------------------------------------------------------------------------------------------- |
| T0         | Observed DNS failures from pods using `10.32.0.10` as resolver.                                 |
| T0+5m      | Verified CoreDNS pods were Running and responding locally.                                      |
| T0+15m     | Found IPVS service entries for `10.32.0.10:53` but inconsistent hit/miss behavior.              |
| T0+30m     | Ran `dig` loops — \~50% of requests failed with `connection timed out`.                         |
| T0+50m     | Checked kube-proxy mode → confirmed IPVS mode active.                                           |
| T0+55m     | Reviewed `iptables-save` — NAT table rules present but mismatched between nodes.                |
| T1h        | Discovered **node-0** was using `iptables-nft` backend, node-1 was using `iptables-legacy`.     |
| T1h10m     | Switched node-0 to `iptables-legacy` backend, restarted kube-proxy, flushed IPVS and conntrack. |
| T1h20m     | Re-tested with loop — 10/10 successful DNS responses.                                           |
| T1h30m     | Uncordoned node-0, scaled CoreDNS, and confirmed HA resolution across nodes.                    |

---

## **3. Symptoms**

* **Intermittent DNS resolution** from workloads:

  * Some `dig`/`nslookup` calls succeeded immediately.
  * Others timed out completely.
* Failures were random and not tied to a specific CoreDNS pod.
* From IPVS inspection:

  ```bash
  ipvsadm -ln -u 10.32.0.10:53
  ```

  Showed only one CoreDNS backend active on node-0, with inconsistent routing.

---

## **4. Root Cause Analysis**

### **Technical Factors**

* **Kube-proxy in IPVS mode** depends on `iptables` NAT rules to direct cluster service traffic to the correct IPVS virtual servers.
* Node-0 was using the **iptables-nft** backend, while node-1 used **iptables-legacy**.
* **iptables-nft** created subtle rule mismatch — kube-proxy could not program certain DNAT rules correctly, resulting in traffic drops or bypassing the service VIP.

### **Consequence**

When workloads on node-0 attempted to reach `10.32.0.10`, some requests were:

* Routed correctly → success.
* Dropped / misrouted due to missing NAT entries → timeout.

---

## **5. Diagnostics Performed**

### Service & Pod Verification

```bash
kubectl -n kube-system get svc coredns -o wide
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
```

→ Both CoreDNS pods running on separate nodes.

### IPVS Verification

```bash
ipvsadm -ln | grep '10.32.0.10:53'
```

→ Showed VIP with backends, but one node not receiving traffic consistently.

### DNS Query Loop

```bash
kubectl run dnst --rm -i --restart=Never --image=infoblox/dnstools:latest --command -- \
  sh -lc 'for i in $(seq 1 10); do echo TRY $i; dig +time=1 +retry=0 @10.32.0.10 kubernetes.default.svc.cluster.local +short || echo TIMEOUT; done'
```

→ Intermittent TIMEOUTs observed.

### iptables Backend Check

```bash
update-alternatives --config iptables
```

→ Node-0: `iptables-nft` (20 priority) in auto mode
→ Node-1: `iptables-legacy` (10 priority) in manual mode

---

## **6. Resolution Steps**

### **On node-0**

1. Switch backend:

```bash
sudo update-alternatives --config iptables
# Select: /usr/sbin/iptables-legacy
sudo update-alternatives --config ip6tables
# Select: /usr/sbin/ip6tables-legacy
```

2. Restart kube-proxy:

```bash
sudo systemctl restart kube-proxy
```

3. Clear stale entries:

```bash
sudo ipvsadm -C
sudo conntrack -F
```

4. Verify:

```bash
ipvsadm -ln | grep 10.32.0.10:53
```

### **Cluster-Wide**

* Rolled CoreDNS deployment:

```bash
kubectl -n kube-system rollout restart deploy/coredns
```

* Uncordoned node:

```bash
kubectl uncordon node-0
```

---

## **7. Post-Fix Verification**

### DNS Loop Test (Success)

```bash
TRY 1
10.32.0.1
...
TRY 10
10.32.0.1
```

→ **100% success rate**.

### Endpoint Health

```bash
kubectl -n kube-system get endpoints coredns -o wide
```

→ Both pods listed as ready endpoints.

---

## **8. Preventive Actions**

* **Standardize kube-proxy backend** → enforce `iptables-legacy` on all nodes.
* **Add startup checks** in provisioning scripts to ensure consistent backend selection.
* **Automated DNS health probe** (CronJob) to run `dig` every minute and log failures.
* **Anti-affinity for CoreDNS** to ensure pods always land on different nodes.

---

## **9. Lessons Learned**

* Mixed iptables backends can silently break kube-proxy service routing in IPVS mode.
* Intermittent DNS issues often point to **partial service VIP rule programming**.
* Always verify **both IPVS table entries and NAT iptables rules** when debugging.

