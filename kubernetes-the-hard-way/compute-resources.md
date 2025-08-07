# Kubernetes Compute Resources Provisioning Guide

## Overview

This guide provides step-by-step instructions for provisioning compute resources required to set up a Kubernetes cluster. The process involves configuring machines to host the Kubernetes control plane and worker nodes where containers will be deployed.

## Prerequisites

- Access to three machines (physical or virtual)
- SSH connectivity between machines
- Root or sudo access on all machines
- A jumpbox machine for orchestrating the setup

## Architecture

The tutorial uses the following machine roles:

| Role | Purpose | Components |
|------|---------|------------|
| Server | Control Plane | Kubernetes API server, etcd, controller manager |
| Node-0 | Worker Node | kubelet, kube-proxy, container runtime |
| Node-1 | Worker Node | kubelet, kube-proxy, container runtime |

## Machine Database Configuration

### Schema Definition

Create a machine database using a text file with the following schema:

```
IPV4_ADDRESS FQDN HOSTNAME POD_SUBNET
```

**Field Descriptions:**
- **IPV4_ADDRESS**: Machine's IP address
- **FQDN**: Fully qualified domain name
- **HOSTNAME**: Short hostname for the machine
- **POD_SUBNET**: Unique IP range for pod networking (CIDR notation)

### Sample Configuration

Create `machines.txt` with your machine details:

```bash
# Example format (replace XXX.XXX.XXX.XXX with actual IPs)
XXX.XXX.XXX.XXX server.kubernetes.local server 10.200.0.0/24
XXX.XXX.XXX.XXX node-0.kubernetes.local node-0 10.200.1.0/24
XXX.XXX.XXX.XXX node-1.kubernetes.local node-1 10.200.2.0/24
```

## SSH Access Configuration

### Enable Root SSH Access

**⚠️ Security Notice:** This configuration is for lab environments only. Production deployments should use more secure authentication methods.

On each target machine, perform the following steps:

1. **Login and switch to root:**
   ```bash
   su - root
   ```

2. **Enable root SSH login:**
   ```bash
   sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
   ```

3. **Restart SSH service:**
   ```bash
   systemctl restart sshd
   ```

### SSH Key Generation and Distribution

Execute these commands from the **jumpbox machine**:

1. **Generate SSH keypair:**
   ```bash
   ssh-keygen -t rsa -b 4096
   ```
   *Note: Press Enter for all prompts to use defaults and no passphrase*

2. **Copy private key to jumpbox (if using cloud instances):**
   ```bash
   # Example for AWS EC2 instances
   scp -i your-key.pem your-key.pem admin@jumpbox-ip:~/
   sudo mv /home/admin/your-key.pem /root/
   sudo chmod 400 /root/your-key.pem
   ```

3. **Distribute public key to all machines:**
   ```bash
   for ip in $(awk '{print $1}' machines.txt); do
     echo "Copying SSH key to root@$ip ..."
     ssh -i /root/your-key.pem admin@$ip \
       "sudo mkdir -p /root/.ssh && \
        sudo chmod 700 /root/.ssh && \
        echo '$(cat /root/.ssh/id_rsa.pub)' | \
        sudo tee -a /root/.ssh/authorized_keys > /dev/null && \
        sudo chmod 600 /root/.ssh/authorized_keys"
   done
   ```

4. **Verify SSH access:**
   ```bash
   while read IP FQDN HOST SUBNET; do
     ssh -n root@${IP} hostname
   done < machines.txt
   ```

   **Expected output:**
   ```
   server
   node-0
   node-1
   ```

## Hostname Configuration

### Set Machine Hostnames

Execute from the jumpbox to configure hostnames on all machines:

```bash
while read IP FQDN HOST SUBNET || [ -n "$IP" ]; do
  echo "🔧 Setting hostname and FQDN entry for $HOST ($IP)..."
  
  # Set short hostname
  ssh -n root@$IP "hostnamectl set-hostname $HOST"
  
  # Update /etc/hosts with FQDN mapping
  ssh -n root@$IP "sed -i '/127.0.1.1/d' /etc/hosts && \
                   echo '127.0.1.1 $FQDN $HOST' >> /etc/hosts"
  
  # Restart hostname service
  ssh -n root@$IP "systemctl restart systemd-hostnamed"
done < machines.txt
```

### Verify Hostname Configuration

```bash
echo -e "\n🔍 Verifying hostname and FQDN..."
while read IP FQDN HOST SUBNET || [ -n "$IP" ]; do
  echo "📍 $IP"
  ssh -n root@$IP "echo -n 'hostname: '; hostname"
  ssh -n root@$IP "echo -n 'fqdn:     '; hostname --fqdn"
  echo
done < machines.txt
```

**Expected output format:**
```
📍 10.240.0.70
hostname: server
fqdn:     server.kubernetes.local

📍 10.240.0.71
hostname: node-0
fqdn:     node-0.kubernetes.local
```

## Host Lookup Table Setup

### Generate Hosts File

Create a consolidated hosts file for DNS resolution:

1. **Initialize hosts file:**
   ```bash
   echo "" > hosts
   echo "# Kubernetes The Hard Way" >> hosts
   ```

2. **Generate host entries:**
   ```bash
   while read IP FQDN HOST SUBNET; do
       ENTRY="${IP} ${FQDN} ${HOST}"
       echo $ENTRY >> hosts
   done < machines.txt
   ```

3. **Review generated entries:**
   ```bash
   cat hosts
   ```

### Update Local Machine Hosts File

Add the host entries to the jumpbox `/etc/hosts` file:

```bash
cat hosts >> /etc/hosts
```

**Verify the update:**
```bash
cat /etc/hosts
```

### Distribute Hosts File to Remote Machines

Copy and apply the hosts file to all cluster machines:

```bash
while read IP FQDN HOST SUBNET; do
  scp hosts root@${HOST}:~/
  ssh -n root@${HOST} "cat hosts >> /etc/hosts"
done < machines.txt
```

## Verification and Testing

### Connectivity Test

Test hostname-based connectivity from the jumpbox:

```bash
# Test SSH connectivity using hostnames
for host in server node-0 node-1; do
  echo "Testing connection to $host..."
  ssh -n root@$host "echo 'Connection successful to $(hostname)'"
done
```

### Network Connectivity Verification

Verify inter-node connectivity:

```bash
# Test from each node to all other nodes
while read IP FQDN HOST SUBNET; do
  echo "Testing from $HOST:"
  ssh -n root@$HOST "
    for target in server node-0 node-1; do
      if [ \$target != $HOST ]; then
        ping -c 1 \$target > /dev/null 2>&1 && \
        echo '  ✓ \$target reachable' || \
        echo '  ✗ \$target unreachable'
      fi
    done
  "
done < machines.txt
```
