# Next Steps — Homelab Deployment
**Updated:** 2026-03-15
**Status:** Blocked on SSH key authorization to Proxmox nodes

---

## Step 0: Unblock SSH Access (Do This First)

On each Proxmox node via **web console** (Datacenter → Node → Shell):

```bash
mkdir -p /root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMawuDramMv3J+OhvLU+3jTh0nATlDeilswb7zFR0JUV jeremy@Shoop" \
  >> /root/.ssh/authorized_keys
chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
```

Run on: **pve01, pve02, pve03-7090, pve04-7090**

Then verify: `ssh pve01 "hostname"` (uses ~/.ssh/config shortcuts now configured)

---

## Step 1: Fix ubuntu-docker VM (pve02 console or after SSH access)

### 1a. Fix boot disk misconfiguration
```bash
# On pve02 (via web console or SSH once keys added):
qm set 100 --bootdisk virtio0
qm reboot 100
```

### 1b. Check VM IP after reboot
```bash
# From this machine after VM reboots:
ssh ubuntu@192.168.4.20 "hostname && ip addr show"
# If still unreachable, check DHCP leases on router at 192.168.4.1
```

### 1c. Install qemu-guest-agent (via jump host once pve02 SSH works)
```bash
ssh -J root@192.168.4.11 ubuntu@192.168.4.20 "
  sudo apt update &&
  sudo apt install -y qemu-guest-agent &&
  sudo systemctl enable --now qemu-guest-agent &&
  sudo systemctl status qemu-guest-agent --no-pager
"
```

---

## Step 2: Install Docker on ubuntu-docker

```bash
# Install Docker CE
ssh ubuntu-docker "curl -fsSL https://get.docker.com | sudo sh"
ssh ubuntu-docker "sudo usermod -aG docker ubuntu"
ssh ubuntu-docker "sudo apt install -y docker-compose-plugin"

# Test
ssh ubuntu-docker "docker run --rm hello-world"
ssh ubuntu-docker "docker compose version"
```

---

## Step 3: Sync /etc/hosts to All Proxmox Nodes

Once SSH keys are authorized:

```bash
# Create the hosts file
cat > /tmp/hosts.cluster << 'EOF'
127.0.0.1       localhost
192.168.4.10    pve01.homelab.local pve01
192.168.4.11    pve02.homelab.local pve02
192.168.4.12    pve03-7090.homelab.local pve03-7090
192.168.4.13    pve04-7090.homelab.local pve04-7090
192.168.4.2     pihole-dns.homelab.local pihole
192.168.4.5     truenas-nfs.homelab.local truenas
192.168.4.15    ai-node-a4500.homelab.local ai-node
192.168.4.20    ubuntu-docker.homelab.local docker-host

::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# Push to all nodes
for node in pve01 pve02 pve03-7090 pve04-7090; do
    scp /tmp/hosts.cluster root@$node:/etc/hosts && echo "$node ✅" || echo "$node ❌"
done

# Verify hostname resolution
for node in pve01 pve02 pve03-7090 pve04-7090; do
    ssh root@192.168.4.10 "ping -c 1 $node -W 2" && echo "$node resolves ✅" || echo "$node failed ❌"
done
```

---

## Step 4: Create AI Node VM on pve01 (Quadro P4000)

```hcl
# terraform/proxmox-homelab/ai-node-pve01.tf
resource "proxmox_vm_qemu" "ai_node_pve01" {
  name        = "ai-node-p4000"
  target_node = "pve01"
  clone       = "ubuntu-2404-cloud"
  full_clone  = true
  cores       = 8
  sockets     = 1
  memory      = 32768   # 32GB
  cpu_type    = "host"
  bios        = "seabios"
  boot        = "c"
  bootdisk    = "virtio0"
  agent       = 1
  os_type     = "cloud-init"

  disk {
    slot     = "virtio0"
    size     = "100G"
    storage  = "local-lvm"
    discard  = "on"
  }

  network {
    model    = "virtio"
    bridge   = "vmbr0"
  }

  # PCI Passthrough — Quadro P4000
  hostpci {
    id     = "hostpci0"
    pcie   = true
    rombar = true
    pciid  = "0000:01:00"  # pve01: GP104GL [Quadro P4000]
  }

  ipconfig0  = "ip=192.168.4.15/22,gw=192.168.4.1"
  ciuser     = "ubuntu"
  sshkeys    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMawuDramMv3J+OhvLU+3jTh0nATlDeilswb7zFR0JUV jeremy@Shoop"
}
```

**Apply:**
```bash
cd terraform/proxmox-homelab
terraform plan -target=proxmox_vm_qemu.ai_node_pve01
terraform apply -target=proxmox_vm_qemu.ai_node_pve01
```

---

## Step 5: Deploy Ollama on AI Node

```bash
ssh ubuntu@192.168.4.15 << 'EOF'
# Install NVIDIA drivers
sudo apt update && sudo apt install -y nvidia-driver-535 nvidia-utils-535

# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Enable and start service
sudo systemctl enable --now ollama

# Pull models
ollama pull llama3.2
ollama pull nomic-embed-text

# Test
ollama run llama3.2 "say hello"
EOF
```

---

## Step 6: AnythingLLM Docker Compose (ubuntu-docker)

Create `/opt/anythingllm/docker-compose.yml` on ubuntu-docker:

```yaml
version: "3.8"

services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: anythingllm
    restart: unless-stopped
    ports:
      - "3001:3001"
    environment:
      STORAGE_DIR: /app/server/storage
      LLM_PROVIDER: ollama
      OLLAMA_BASE_PATH: http://192.168.4.15:11434
      EMBEDDING_ENGINE: ollama
      EMBEDDING_MODEL_PREF: nomic-embed-text
      OLLAMA_EMBEDDING_BASE_PATH: http://192.168.4.15:11434
      VECTOR_DB: lancedb
    volumes:
      - anythingllm_storage:/app/server/storage

volumes:
  anythingllm_storage:
```

**Deploy:**
```bash
ssh ubuntu-docker "mkdir -p /opt/anythingllm"
scp /opt/anythingllm/docker-compose.yml ubuntu-docker:/opt/anythingllm/
ssh ubuntu-docker "cd /opt/anythingllm && docker compose up -d"
# Access: http://192.168.4.20:3001
```

---

## Step 7: LiteLLM Proxy Configuration (ubuntu-docker)

Create `/opt/litellm/config.yaml` on ubuntu-docker:

```yaml
model_list:
  - model_name: llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://192.168.4.15:11434

  - model_name: nomic-embed-text
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: http://192.168.4.15:11434

litellm_settings:
  drop_params: true
  success_callback: []

general_settings:
  master_key: sk-homelab-litellm-key
```

**docker-compose.yml for LiteLLM:**
```yaml
version: "3.8"
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    ports:
      - "4000:4000"
    volumes:
      - ./config.yaml:/app/config.yaml
    command: ["--config", "/app/config.yaml", "--port", "4000", "--detailed_debug"]
```

**Deploy:**
```bash
ssh ubuntu-docker "mkdir -p /opt/litellm"
# Copy config files...
ssh ubuntu-docker "cd /opt/litellm && docker compose up -d"
# Test: curl http://192.168.4.20:4000/v1/models
```

---

## Step 8: Fix Corosync Ring0 IPs (Non-Critical)

The corosync status shows old IPs for pve01 (.2), pve03 (.3), pve04 (.4).
These should be updated to match the new /22 addressing scheme (.10, .12, .13).

> ⚠️ **WARNING:** Editing corosync.conf incorrectly can break cluster quorum.
> Follow the Proxmox docs procedure: https://pve.proxmox.com/wiki/Cluster_Manager

```bash
# Check current corosync config (on pve01 after SSH works):
ssh pve01 "cat /etc/pve/corosync.conf"

# Update ring0_addr values for each node block:
# node pve01: ring0_addr: 192.168.4.10
# node pve03-7090: ring0_addr: 192.168.4.12
# node pve04-7090: ring0_addr: 192.168.4.13
# (pve02 already shows correct .11)

# After updating, reload corosync on all nodes:
ssh pve01 "systemctl restart corosync"
```

---

## Quick Reference — Homelab IPs

| Host | IP | Role |
|:-----|:---|:-----|
| pve01 | 192.168.4.10 | Proxmox node 1 (Quadro P4000) |
| pve02 | 192.168.4.11 | Proxmox node 2 (RTX A4500) |
| pve03-7090 | 192.168.4.12 | Proxmox node 3 |
| pve04-7090 | 192.168.4.13 | Proxmox node 4 |
| pihole | 192.168.4.2 | DNS / ad-block |
| truenas | 192.168.4.5 | NAS / NFS |
| ubuntu-docker | 192.168.4.20 | Docker host |
| ai-node | 192.168.4.15 | AI inference (planned) |
