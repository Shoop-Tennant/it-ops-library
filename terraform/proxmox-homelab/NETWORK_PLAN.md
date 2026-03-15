# Network Plan — Proxmox Homelab

**Subnet:** `192.168.4.0/22` (covers `192.168.4.0`–`192.168.7.255`)
**Gateway:** `192.168.4.1` (Eero)

---

## Cluster IP Migration Complete ✅

All 4 Proxmox nodes have been migrated to the `/22` subnet with new management IPs.
Cluster quorum verified with 4/4 nodes voting.

| Node | Old IP | New IP | Role |
|:-----|:-------|:-------|:-----|
| pve01 | 192.168.4.2 | 192.168.4.10 | Operations Hub — DNS, Tailscale, quorum |
| pve02 | 192.168.4.20 | 192.168.4.11 | AI R&D Engine — RTX A4500, Docker/Ollama |
| pve03 | 192.168.4.3 | 192.168.4.12 | Enterprise Stage — Windows Server, SAP/Helix |
| pve04 | 192.168.4.4 | 192.168.4.13 | Data & Media — PBS, Plex/Jellyfin |

---

## Full IP Allocations

| IP | Hostname | Type | Node | Managed By | Notes |
|:---|:---------|:-----|:-----|:-----------|:------|
| 192.168.4.1 | eero-gw | Router | — | Manual | Default gateway |
| 192.168.4.2 | pihole-dns | LXC | pve01 | Terraform | Pi-hole DNS server |
| 192.168.4.5 | truenas | Physical | — | Manual | NFS storage (RAIDZ1 4×2TB) |
| 192.168.4.10 | pve01 | Physical | pve01 | Manual | Proxmox management + Terraform API target |
| 192.168.4.11 | pve02 | Physical | pve02 | Manual | Proxmox management |
| 192.168.4.12 | pve03 | Physical | pve03 | Manual | Proxmox management |
| 192.168.4.13 | pve04 | Physical | pve04 | Manual | Proxmox management |
| 192.168.4.20 | ubuntu-docker | VM | pve02 | Terraform | Docker/Ollama host, RTX A4500 passthrough |

---

## Planned / Reserved

| IP Range | Purpose |
|:---------|:--------|
| 192.168.4.30 | pve03 Windows Server VM (future Terraform) |
| 192.168.4.14–19 | Node/infrastructure expansion |
| 192.168.4.21–29 | pve02 VM expansion pool |
| 192.168.5.0/24 | Reserved for future VLAN/tenant testing |
