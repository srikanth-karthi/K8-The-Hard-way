# **Understanding Why MetalLB Fails to Talk to the Kubernetes API (SAN Context)**

## 1. **Background: How Kubernetes API Access Works**

Every Kubernetes cluster has an **API server** (`kube-apiserver`) that acts as the central control plane endpoint.
Different components talk to it in different ways:

| Component Location           | How It Reaches API Server                               | Typical Target Address           | DNS Involved?     |
| ---------------------------- | ------------------------------------------------------- | -------------------------------- | ----------------- |
| **Pods inside the cluster**  | Through the `kubernetes` Service in `default` namespace | ClusterIP (e.g., `10.240.0.65`)  | Yes (via CoreDNS) |
| **kubelet on nodes**         | Uses its own `kubeconfig`                               | Master private IP / NLB hostname | No (direct)       |
| **kube-proxy**               | Uses its own `kubeconfig`                               | Master private IP / NLB hostname | No (direct)       |
| **kubectl on admin machine** | Uses the admin `kubeconfig`                             | Master private IP / NLB hostname | No (direct)       |

---

## 2. **Inside-the-Cluster Path**

When a pod (like MetalLB controller) needs to talk to the Kubernetes API:

1. **Pod code** calls the API endpoint using the default Kubernetes service name:

   ```
   https://kubernetes.default.svc
   ```
2. Inside the pod, **CoreDNS** resolves `kubernetes.default.svc` to the **ClusterIP** of the API server service.

   ```
   10.240.0.65   ← Example ClusterIP for `kubernetes` Service
   ```
3. The pod initiates a TLS handshake to `10.240.0.65:443`.

---

## 3. **TLS Certificate Matching (SAN Check)**

During that handshake:

* The API server sends its **TLS certificate** to the client (pod).
* The client checks the **Subject Alternative Name (SAN)** list inside the certificate.
* **The rule:** The SAN list **must** include the exact IP or DNS name that the client used to connect.

If the pod connects to `10.240.0.65` but the cert’s SAN list **does not** contain `10.240.0.65` →
The TLS handshake fails with:

```
x509: certificate is valid for ... not 10.240.0.65
```

---

## 4. **Why This Breaks MetalLB (and Similar Pods)**

* MetalLB’s controller pod runs *inside* the cluster.
* It tries to connect to the API server via `kubernetes.default.svc` → resolves to ClusterIP.
* Because the ClusterIP is **missing from the SAN list**, TLS verification fails.
* Result: MetalLB can’t register, can’t read/write resources, and crashes.

---

## 5. **Why kubelet / kube-proxy Still Work**

* **kubelet** and **kube-proxy** don’t use the in-cluster DNS path.
  They connect using the IP or DNS set in their kubeconfig (often the NLB or master node IP).
* That IP/DNS *is* already in the API server cert’s SAN list.
* So their TLS handshake passes, and they can report pod status, watch objects, etc.

---

## 6. **Key Points**

* **ClusterIP is for in-cluster communication** → required for pods that use `kubernetes.default.svc`.
* **SAN mismatch only affects clients that connect via the missing SAN name/IP**.
* If SAN doesn’t contain ClusterIP, **all pods talking via service name will fail**, but node-level daemons will continue to work.

