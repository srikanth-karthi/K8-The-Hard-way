

# **Pod Communication with the Kubernetes API Server**

## **1. Overview**

In Kubernetes, all Pods can communicate with the **kube-apiserver** — the control-plane component that serves as the single entry point to manage the cluster.
This communication is used for:

* Reporting Pod and Node status
* Fetching configuration and secrets
* Watching for changes in the cluster
* Updating Kubernetes resources

The connection is abstracted using a **ClusterIP Service** called `kubernetes`, making it independent of the real master node IP addresses.

---

## **2. Key Components in the Communication Path**

### **2.1 Service Account Injection**

When Kubernetes creates a Pod:

* It **mounts** the default **ServiceAccount token** at:

  ```
  /var/run/secrets/kubernetes.io/serviceaccount/token
  ```
* It **mounts** the cluster’s CA certificate at:

  ```
  /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  ```
* It injects API server connection details into environment variables:

  ```bash
  KUBERNETES_SERVICE_HOST=10.240.0.65
  KUBERNETES_SERVICE_PORT=443
  ```

---

### **2.2 Built-in Kubernetes Service**

The API server is exposed as a **Service** in the `default` namespace:

```bash
kubectl get svc kubernetes
```

Example output:

```
NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
kubernetes    ClusterIP   10.240.0.65    <none>        443/TCP   …
```

* **ClusterIP** (`10.240.0.65` here) is **virtual** — no physical interface exists with that IP.
* **kube-proxy** configures iptables/ipvs rules so traffic to `10.240.0.65:443` is sent to one of the **master node IPs** (e.g., `10.240.0.70`, `10.240.0.71`).

---

### **2.3 DNS Resolution**

Inside any Pod:

```bash
nslookup kubernetes.default.svc
```

This resolves to the API server’s ClusterIP (`10.240.0.65`).
DNS is managed by **CoreDNS** in the `kube-system` namespace.

---

### **2.4 Traffic Flow**

**Example path when a Pod reports its status:**

```
Pod → DNS lookup (kubernetes.default.svc) → ClusterIP (10.240.0.65)  
   → kube-proxy routing → Real master IP (10.240.0.70 / 10.240.0.71)  
   → kube-apiserver → etcd
```

---

## **3. Why This Design?**

1. **Abstraction of Master IPs**

   * Pods do not store or rely on physical master IPs.
   * Masters can be replaced or scaled without Pod reconfiguration.

2. **Service Discovery**

   * `kubernetes.default.svc` is automatically available in every namespace.
   * No need for hardcoded IPs.

3. **Security**

   * Every Pod uses an automatically mounted ServiceAccount token for authentication.
   * The CA certificate ensures secure HTTPS communication.

4. **Scalability & HA**

   * Multiple masters behind the ClusterIP provide high availability.
   * kube-proxy load balances requests.

---

## **4. Components That Talk to the API Server**

### **4.1 Control Plane Components**

* **kube-controller-manager**
* **kube-scheduler**
* **cloud-controller-manager**

### **4.2 Node Agents**

* **kubelet** – Node registration, Pod lifecycle updates.
* **kube-proxy** – Watches Services/Endpoints.

### **4.3 Add-ons**

* **CoreDNS** – Watches Services for DNS updates.
* **CNI plugins** – Watch network policy changes.
* **Metrics-server** – Reports cluster metrics.

### **4.4 Application Pods**

* Only if explicitly coded to use the Kubernetes API.

---

## **5. Visual Diagram**

```
[Pod] -- https://kubernetes.default.svc --> [ClusterIP: 10.240.0.65]  
   → [kube-proxy] → [Master IPs: 10.240.0.70 / 10.240.0.71]  
      → [kube-apiserver] → [etcd]
```

---

## **6. How to Verify in Your Cluster**

1. **Check the built-in Kubernetes Service:**

```bash
kubectl get svc kubernetes
```

2. **Resolve DNS from inside a Pod:**

```bash
kubectl run -it --rm testpod --image=busybox --restart=Never -- nslookup kubernetes.default.svc
```

3. **Test API server connectivity:**

```bash
kubectl run -it --rm testpod --image=busybox --restart=Never -- wget --no-check-certificate https://kubernetes.default.svc
```

4. **Check the token and CA cert:**

```bash
kubectl exec -it testpod -- cat /var/run/secrets/kubernetes.io/serviceaccount/token
kubectl exec -it testpod -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```
