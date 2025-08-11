# **MetalLB in a Bare-Metal Kubernetes Cluster (2 Masters + 2 Workers)**

## **1. Introduction**

Kubernetes `Service.type=LoadBalancer` normally depends on cloud provider integrations (e.g., AWS ELB, Azure Load Balancer) to allocate and advertise an external IP.
On **bare-metal clusters**, there’s no cloud controller to do this. **MetalLB** fills that gap by providing an implementation of LoadBalancer services using standard networking protocols.

---

## **2. Your Cluster Setup**

**Nodes:**

* **Master 1** – `192.168.1.101`
* **Master 2** – `192.168.1.102`
* **Worker 1** – `192.168.1.103`
* **Worker 2** – `192.168.1.104`

**Goal:**
Allow external clients on the LAN to access services in the cluster using stable IP addresses, without needing a separate physical load balancer.

---

## **3. MetalLB Components**

MetalLB installs into the cluster and runs as Kubernetes resources:

| Component      | Type       | Runs On                       | Purpose                                                                  |
| -------------- | ---------- | ----------------------------- | ------------------------------------------------------------------------ |
| **Controller** | Deployment | One pod (in `metallb-system`) | Watches for `LoadBalancer` Services, allocates IPs from configured pool. |
| **Speaker**    | DaemonSet  | All nodes                     | Announces assigned service IPs to the LAN so clients can route traffic.  |

---

## **4. Address Pools**

You must configure a **pool of unused IP addresses** from your LAN/subnet:

* Must be **in the same subnet** as your node IPs.
* Must **not** overlap with DHCP-assigned addresses or other devices.
* Example:

  ```
  192.168.1.200-192.168.1.210
  ```

These will be assigned to LoadBalancer services.

---

## **5. Operation Modes**

### **5.1 Layer-2 Mode (most common on bare metal)**

* **How it works:**

  * One node is elected “owner” of a service IP.
  * That node’s Speaker pod responds to **ARP** (IPv4) or **NDP** (IPv6) requests:

    > “I have 192.168.1.200 — send traffic to me.”
  * All traffic for that IP enters through the leader node.
  * kube-proxy forwards packets to the correct pod(s) across the cluster.
* **Failover:**

  * If leader node fails, another node takes over IP ownership within \~1s.

**Pros:** Easy to set up, no router changes.
**Cons:** All traffic for that service passes through one node (possible bottleneck).

---

### **5.2 BGP Mode (advanced)**

* Nodes peer with your network routers via BGP.
* All capable nodes advertise a route to the service IP.
* Routers load-balance traffic across multiple nodes.

**Pros:** True multi-node load balancing.
**Cons:** Requires router control and BGP knowledge.

---

## **6. Step-by-Step Flow (Layer-2 in Your Cluster)**

### **Example Service**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: myapp
```

---

### **Sequence of Events**

1. **Service Creation**

   * You create the `myapp` LoadBalancer service.
2. **IP Allocation**

   * Controller assigns `192.168.1.200` from the pool.
   * Updates the service’s status with that IP.
3. **Leader Election**

   * All nodes run Speakers; one (e.g., Worker1) is chosen as owner for this IP.
4. **IP Announcement**

   * Worker1 Speaker responds to ARP queries for `192.168.1.200` with its MAC.
5. **Traffic Flow**

   * Client sends packet to `192.168.1.200:80`.
   * LAN switch routes it to Worker1.
   * kube-proxy sends it to a backend pod (local or remote).
6. **Failover**

   * If Worker1 fails, another node (e.g., Worker2) takes over and starts ARPing for `192.168.1.200`.

---

## **7. Deployment Steps (Layer-2)**

1. **Install MetalLB**

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
```

2. **Create IP Address Pool**

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: pool-1
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.200-192.168.1.210
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: adv-1
  namespace: metallb-system
spec:
  ipAddressPools:
    - pool-1
```

```bash
kubectl apply -f ip-pool.yaml
```

3. **Test**

```bash
kubectl create deploy echo --image=nginxdemos/hello
kubectl expose deploy echo --type=LoadBalancer --port=80 --target-port=80
kubectl get svc echo -w
```

---

## **8. Diagram — Layer-2 Mode in Your Cluster**

```
Client ----(ARP)----> "Who has 192.168.1.200?"
Worker1 Speaker ----> "I do" (MAC=aa:bb:cc)
Client ----(TCP/80)--> Worker1 ----> kube-proxy ----> Pod (any node)

If Worker1 fails:
Worker2 Speaker ----> "I do" → becomes new traffic entry point
```

---

## **9. Key Takeaways**

* No separate hardware LB is required — MetalLB uses cluster nodes.
* You must reserve IPs in your LAN subnet for MetalLB’s pool.
* Layer-2 mode is easiest; BGP mode is for advanced routing setups.
* In Layer-2 mode, one node handles all ingress per service; failover is automatic.
