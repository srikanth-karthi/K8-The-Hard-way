# Deep Dive: containerd, CNI, and IP Routing in Kubernetes "The Hard Way"

This document elaborates on:

1. **containerd** – the container runtime
2. **CNI** – Container Network Interface plugins
3. **IP routing** – Linux routing for cross-node Pod networking
4. **How they fit together** – the end-to-end Pod networking and container lifecycle flow

---

## 1. containerd: The Container Runtime

**Purpose:**

* Provides a stable, high-performance runtime for containers.
* Implements the CRI (Container Runtime Interface) to integrate with kubelet.

**Key Components:**

* **gRPC API**: `io.containerd.grpc.v1.cri` plugin handles PodSandbox and Container operations.
* **Snapshotter**: Manages filesystem layers (e.g., `overlayfs`).
* **Runtime**: Invokes `runc` (or other OCI runtimes) to spawn container processes.
* **CNI Integration Block**: Calls CNI plugins to set up networking.

**Configuration Example (`/etc/containerd/config.toml`):**

```toml
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  [plugins."io.containerd.grpc.v1.cri".containerd]
    snapshotter = "overlayfs"
    default_runtime_name = "runc"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
  [plugins."io.containerd.grpc.v1.cri".cni]
    bin_dir  = "/opt/cni/bin"
    conf_dir = "/etc/cni/net.d"
```

* **`SystemdCgroup=true`**: Uses systemd for cgroup management per container.
* **`bin_dir`, `conf_dir`**: Where CNI plugin binaries and configs live.

---

## 2. CNI: Container Network Interface

**Purpose:**

* Defines a standardized way for container runtimes to configure network interfaces in container namespaces.
* Enables pluggable network solutions.

**Plugin Model:**

* **Chain of JSON files** in `/etc/cni/net.d/` executed in lexicographic order.
* Plugins in `/opt/cni/bin/` implement operations (`ADD`, `DEL`, `CHECK`).

**Typical Plugins for "Hard Way":**

1. **bridge** – sets up a Linux bridge and veth pair per Pod.
2. **loopback** – brings up the `lo` interface inside containers.
3. **host-local** – IPAM plugin to allocate IPs from POD CIDR.

**Example: `10-bridge.conf`**

```json
{
  "cniVersion": "1.0.0",
  "name": "bridge",
  "type": "bridge",
  "bridge": "cni0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "ranges": [[{"subnet": "10.200.0.0/24"}]],
    "routes": [{"dst": "0.0.0.0/0"}]
  }
}
```

**Key Fields:**

* **`bridge`**: Host bridge interface name.
* **`isGateway`**: Assigns the bridge IP as gateway.
* **`ipMasq`**: Enables SNAT for Pod egress.
* **`ipam.ranges`**: Pod IP pool per node.

**Example: `99-loopback.conf`**

```json
{
  "cniVersion": "1.1.0",
  "name": "lo",
  "type": "loopback"
}
```

---

1. 10-bridge.conf – Pod-to-Pod / Pod-to-External Networking
Purpose:
Sets up the main Pod network using the bridge CNI plugin.
Creates (or uses) a Linux bridge interface on the node (here cni0).
Connects all Pods on that node to the same L2 network segment.
Assigns IPs to Pods from a defined subnet (via IPAM).
Allows Pod traffic to reach outside the cluster via NAT (ipMasq: true).
In practice:
When a Pod is created, its eth0 is connected to this bridge.
The bridge’s IP acts as the gateway for Pods on that node.
Example flow: Pod → cni0 → Node’s main interface → Internet/other nodes.

2. 99-loopback.conf – Pod Internal Loopback
Purpose:
Ensures loopback networking (lo) works inside each Pod.
Every Pod gets a loopback interface so processes can talk to themselves using localhost or 127.0.0.1.
In practice:
Required for many applications that bind to localhost.
This is always needed even if you use other networking plugins.


## 3. IP Routing: Linux Kernel Forwarding

**Purpose:**

* Enables cross-node Pod-to-Pod traffic by informing each host how to reach remote Pod subnets.

**Why Manual Routes?**

* Each worker has its own Pod CIDR (e.g., `10.200.0.0/24`, `10.200.1.0/24`).
* The VPC routes only know about host IPs, not Pod subnets.

**Commands to Add Routes:**

```bash
# On control-plane (server)
ip route add 10.200.0.0/24 via 10.240.0.80
ip route add 10.200.1.0/24 via 10.240.0.81

# On node-0
ip route add 10.200.1.0/24 via 10.240.0.81
# On node-1
ip route add 10.200.0.0/24 via 10.240.0.80
```

**Effect:**

* Routes direct Pod-subnet traffic to the appropriate node’s host IP.

**Enable Forwarding:**

```bash
sysctl -w net.ipv4.ip_forward=1
# Persist
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-k8s.conf
sysctl --system
```

---

## 4. How It All Fits Together

### End-to-End Pod Networking Flow

This section walks through each phase—from the moment you submit a Pod spec to the API, all the way to a fully networked application container—highlighting the roles of containerd, CNI, Linux routing, and kube-proxy.

1. **Pod Spec Submission**

   * **User action**: `kubectl run nginx --image=nginx`
   * **API Server**: Validates and stores the Pod manifest in etcd under `/registry/pods`.

2. **Kubelet Detection**

   * **Informer loop**: Kubelet watches the API server via informers.
   * **Assignment**: Pod is scheduled to this node; Kubelet sees it in the work queue.

3. **Sandbox Setup**

   * **CRI call**: Kubelet invokes `RunPodSandbox` on containerd with the **PodSandboxConfig** protobuf message, not a file on disk but an in-memory object composed from the Pod spec and kubelet configuration.
   * **PodSandboxConfig contents** include:
     • Metadata: Pod name, namespace, UID
     • Runtime configuration: Linux namespaces (network, PID, IPC), cgroup parent, security context
     • Networking: `sanboxConfig.PortMappings`, DNSConfig, host network flag
     • Labels & annotations: inherited from the Pod manifest
     • Log directory path under `/var/log/pods/...` for the pause container logs
   * **How it is assembled**:

     1. The kubelet reads its own config (`/var/lib/kubelet/kubelet-config.yaml`) for global defaults (e.g., `pod-infra-container-image`, `cgroupDriver`).
     2. It merges that with the PodSpec (from the API server), applying fields like ports, hostNetwork, shareProcessNamespace.
     3. It serializes this into the `PodSandboxConfig` message and sends it to containerd via the CRI gRPC endpoint at `/run/containerd/containerd.sock`.
   * **Pause container**: containerd (via runc) launches a minimal “pause” container using this `PodSandboxConfig`.

* **What it is**: A tiny, purpose-built OCI image (often `k8s.gcr.io/pause:<version>`) whose sole job is to **exist** and **sleep indefinitely**.
* **Primary Role**: Hold open the Pod’s network (and optionally PID) namespace so:

  1. All subsequent application containers in the Pod can **join** this same namespace.
  2. The DNS, CNI interfaces, and IP configuration only need to be set up **once**.
* **Secondary Benefits**:

  * Provides a stable **parent process** for cgroup hierarchy under `/kubepods/...`.
  * Simplifies teardown: killing the pause container naturally cleans up the namespace and veth attachments.
* **Typical Image**: `k8s.gcr.io/pause:3.6` (smallest possible footprint, no busybox or shell).

  * Purpose: Hold the network namespace open and act as the parent for all Pod containers.

4. **CNI ADD Chain Execution**
   **CNI ADD Chain Execution**

   * containerd sets `CNI_COMMAND=ADD` and iterates all JSON configs in `/etc/cni/net.d/`:

     1. **Bridge Plugin**:

        * Ensures a Linux bridge (`cni0`) exists on the host.
        * Creates a veth pair: host end (e.g. `veth1234`) and container end (`eth0`).
        * Moves `eth0` into the pause container’s network namespace.
        * Allocates an IP from the node’s Pod CIDR via host-local IPAM.
        * Configures the container’s default gateway and subnet routes.
        * Applies iptables NAT rules if `ipMasq=true`.
     2. **Loopback Plugin**:

        * Enters the same namespace and brings up the `lo` interface.
   * **Result**: Pause container netns has `eth0` with IP, route, and `lo` up.

5. **Application Container Creation**

   * Kubelet calls `CreateContainer` on containerd for each application container.
   * containerd calls runc, using the existing network namespace of the pause container.
   * App containers inherit `eth0`, `lo`, and all network settings.

6. **Service Proxying (kube-proxy)**

   * kube-proxy (running on each node) watches Service objects.
   * Programs iptables (or IPVS) rules to intercept Service ClusterIP or NodePort traffic and DNAT to Pod IPs.

7. **Linux Packet Forwarding**

   * **Intra-node**: Packets between Pods on the same host traverse the host’s bridge `cni0`.
   * **Inter-node**:

     * Kernel routing table (manual `ip route` entries) matches remote Pod subnet.
     * Forwards packets to the appropriate node’s host IP.
     * That host receives on `eth0`, passes through `cni0`, then to the Pod’s veth.
   * **External to Pod**: SNAT via iptables ensures Pod traffic to external services egress with node IP.

8. **Pod Comes Online**

   * Kubelet probes readiness (`/readyz`) of application container if configured.
   * Updates Pod status (`Running`, `Ready`) in API server.
   * The Pod is now accessible via Service VIPs or directly via its IP.

9. **Cleanup on Pod Deletion**

   * Kubelet invokes containerd `StopContainer` and `RemoveContainer`.
   * containerd calls CNI with `CNI_COMMAND=DEL`, tearing down veth and cleaning up iptables rules.
   * runc cleans up cgroups and deletes the pause container.

---
