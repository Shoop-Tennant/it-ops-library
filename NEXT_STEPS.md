# Next Steps — Proxmox Homelab
**Generated:** 2026-03-15 15:48:48

---

## 0. Fix SSH Access (BLOCKER for all phases)

The deployment workflow could not reach 192.168.4.0/24 from the WSL2 execution environment.
Before re-running, ensure one of the following:

- [ ] Run the deployment script from a host on the homelab LAN, **OR**
- [ ] Add the WSL2 host's public key (`id_ed25519.pub`) to `/root/.ssh/authorized_keys` on all 4 nodes, **AND** ensure a network route exists to 192.168.4.0/24

```bash
# Deploy SSH key to all nodes (run from a host that CAN reach them):
for NODE in 192.168.4.10 192.168.4.11 192.168.4.12 192.168.4.13; do
  ssh-copy-id -i ~/.ssh/id_ed25519.pub root@$NODE
done
```

---

## 1. Cluster Pre-flight (Re-run Phase 1)

Once SSH access is confirmed:

```bash
ssh root@192.168.4.10 'pvecm status; pvecm nodes; cat /etc/hosts'

for NODE in 192.168.4.10 192.168.4.11 192.168.4.12 192.168.4.13; do
  echo "=== $NODE ==="
  ssh root@$NODE 'curl -sk https://127.0.0.1:8006/api2/json/version; df -h | grep truenas-nfs; dmesg | grep -e DMAR -e IOMMU | head -5'
done
```

---

## 2. GPU PCI Address Discovery (Re-run Phase 2)

Populate `terraform/proxmox-homelab/GPU_PCI_ADDRESSES.txt`:

```bash
# pve01 — Quadro P4000
ssh root@192.168.4.10 "lspci -nn | grep '10de:1bb1'"
# Example: 01:00.0 VGA compatible controller: NVIDIA Quadro P4000 [10de:1bb1]
# → PVE01_PCI=0000:01:00.0,pcie=1

# pve02 — RTX A4500
ssh root@192.168.4.11 "lspci -nn | grep '10de:25b6'"
# Example: 01:00.0 VGA compatible controller: NVIDIA RTX A4500 [10de:25b6]
# → PVE02_PCI=0000:01:00.0,pcie=1,x-vga=1
```

---

## 3. AI Node VM (pve01 — Quadro P4000)

- [ ] Create Ubuntu 22.04 LTS VM on pve01 (ID 200, RAM 16GB, 8 vCPU, 100GB disk)
- [ ] Add GPU passthrough using PCI address from `GPU_PCI_ADDRESSES.txt` (PVE01_PCI)
  - Proxmox UI: Hardware → Add → PCI Device → select Quadro P4000
  - Or via CLI: `qm set 200 -hostpci0 0000:XX:00.0,pcie=1`
- [ ] Boot VM, install NVIDIA drivers (CUDA 12.x)
- [ ] Deploy Ollama for fast/real-time inference:

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen2.5:7b
ollama serve
```

- [ ] Add systemd service for Ollama (listen on 0.0.0.0:11434)
- [ ] Tag VM in Proxmox: `ai-inference`, `gpu-passthrough`

---

## 4. RTX A4500 Passthrough (pve02 — ubuntu-docker VM)

- [ ] In Proxmox UI on pve02: VM Hardware → Add → PCI Device
  - Use resource mapping `rtx-a4500` if already configured, or direct PCI address from `GPU_PCI_ADDRESSES.txt` (PVE02_PCI)
- [ ] Inside ubuntu-docker VM, install NVIDIA drivers:

```bash
sudo apt-get install -y nvidia-driver-535 nvidia-cuda-toolkit
sudo reboot
nvidia-smi  # validate
```

- [ ] Deploy Ollama for heavy LLMs:

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull deepseek-r1:8b
ollama pull qwen2.5:14b
```

---

## 5. Docker VM Setup (ubuntu@192.168.4.20) — Re-run Phase 3

```bash
ssh ubuntu@192.168.4.20 'ip addr show | grep 192.168.4.20'
ssh ubuntu@192.168.4.20 'sudo apt-get install -y qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent'
ssh ubuntu@192.168.4.20 'which docker || curl -fsSL https://get.docker.com | sudo sh'
ssh ubuntu@192.168.4.20 'docker --version && docker compose version'
```

---

## 6. AnythingLLM on ubuntu-docker

- [ ] Create `~/stacks/anythingllm/docker-compose.yml`
- [ ] Configure data volume persistence
- [ ] Connect to Confluence/SharePoint for RAG ingestion
- [ ] Expose on port 3001

```yaml
services:
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    ports:
      - "3001:3001"
    volumes:
      - ./data:/app/server/storage
    environment:
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_PATH=http://192.168.4.20:11434
```

---

## 7. LiteLLM Proxy

- [ ] Docker Compose on ubuntu-docker (port 4000)
- [ ] Configure routes to both Ollama instances:
  - `ollama/qwen2.5:7b` → pve01 AI node (192.168.4.15:11434)
  - `ollama/qwen2.5:14b` → ubuntu-docker (localhost:11434)
  - `ollama/deepseek-r1:8b` → ubuntu-docker (localhost:11434)
- [ ] OpenAI-compatible API endpoint: `http://192.168.4.20:4000`

---

## 8. Open WebUI

- [ ] Docker Compose on ubuntu-docker (port 8080)
- [ ] Connect to LiteLLM gateway at `http://192.168.4.20:4000`
- [ ] Enable team access (disable sign-up, pre-create user accounts)
- [ ] Optional: reverse proxy via nginx on pihole-dns (192.168.4.2)

---

## 9. /etc/hosts Sync — Re-run Phase 4

`etc.hosts.cluster` is already written locally. When SSH access is available:

```bash
for NODE in 192.168.4.10 192.168.4.11 192.168.4.12 192.168.4.13; do
  scp etc.hosts.cluster root@$NODE:/etc/hosts.cluster
  ssh root@$NODE 'ping -c1 pve01 && ping -c1 pve02'
done
```

---

## 10. Terraform Apply

- [ ] Verify Terraform Cloud backend is configured in `terraform/proxmox-homelab/providers.tf`
- [ ] Run `terraform init` then `terraform plan` from `terraform/proxmox-homelab/`
- [ ] Review plan — confirm VM IDs, resource pools, network bridges
- [ ] Run `terraform apply`

```bash
cd terraform/proxmox-homelab
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```
