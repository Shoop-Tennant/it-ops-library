# Shoop Think Tank: Enterprise AI & IT Ops Infrastructure

**Mission:** To build a highly available, scalable homelab environment acting as an incubator for AI-assisted IT Service Management (ITSM) products. This infrastructure prototypes workflows for NinjaOne, BMC Helix, SAP S/4HANA, and Jira before enterprise deployment.

This is not a traditional homelab; it is an "Infrastructure as Code" (IaC) driven platform utilizing a 4-node Proxmox VE cluster, TrueNAS NFS shared storage, and distributed GPU compute.

---

## 1. Physical Architecture & Workload Allocation

The environment relies on a 4-node Proxmox cluster (`Shoop-Homelab`) with specialized roles to distribute workloads efficiently.

| Node | Hardware | Role / Persona | Core Workloads |
| :--- | :--- | :--- | :--- |
| **pve01** | Dell Precision 3630 (IP: 192.168.4.2) | **The Operations Hub** | DNS (AdGuard), Tailscale, Proxmox Quorum. **GPU:** Quadro P4000 [10de:1bb1] for fast, real-time ticket triage (Qwen 2.5 7B). |
| **pve02** | Dell Precision 7670 (IP: 192.168.4.20) | **The AI R&D Engine** | Ubuntu VM via GPU Passthrough. **GPU:** RTX A4500 [10de:25b6] dedicated to heavy LLMs (DeepSeek-R1, Qwen 14B) via Docker/Ollama. |
| **pve03** | Dell OptiPlex 7090 (IP: 192.168.4.3) | **The Enterprise Stage** | Windows Server 2022 on ZFS mirrored SSDs. Staging ground for NinjaOne, SAP S/4HANA, and BMC Helix integration testing. |
| **pve04** | Dell OptiPlex 7090 (IP: 192.168.4.4) | **Data & Media** | High-availability node. Runs Proxmox Backup Server (PBS) and Plex/Jellyfin utilizing Intel QuickSync. |

---

## 2. Storage Strategy

We utilize a hybrid approach, separating high-IOPS boot drives from bulk storage to ensure VM performance.

* **Local Node Storage (NVMe/ZFS SSDs):** Used strictly for Proxmox OS, VM/LXC boot disks, and high-speed databases.
* **TrueNAS SCALE (IP: 192.168.4.5):** 4x2TB RAIDZ1. Provides the `truenas-nfs` share mounted across all four Proxmox nodes.
    * **ISO Location:** `/mnt/pve/truenas-nfs/template/iso` (accessible to Terraform for rapid VM deployment).
    * **Backups:** Dedicated NFS datastore for Proxmox Backup Server.

---

## 3. Network & Connectivity Plan

**Base Subnet:** `192.168.4.0/24` (Eero Gateway: `192.168.4.1`)
**Switching:** NETGEAR GS308EP (Flat network, VLANs reserved for future multi-tenant testing).

* **Tailscale:** Deployed at the routing layer to provide secure, zero-trust remote access. `MagicDNS` is used to resolve hostnames (e.g., `pve01.shoop-lab.ts.net`) without exposing ports to the public internet.

---

## 4. The AI Tech Stack

All AI tooling is self-hosted to guarantee 100% data sovereignty and compliance with corporate data policies.

* **Ollama:** The backend inference engine running across both GPUs (A4500 and P4000).
* **LiteLLM:** Acts as the unified API gateway. Translates OpenAI API calls from PowerShell scripts/Jira integrations into local Ollama queries.
* **AnythingLLM:** The RAG (Retrieval-Augmented Generation) frontend. Connects to Confluence/SharePoint to allow the team to query internal KB articles and SOPs securely.
* **Open WebUI:** The ChatGPT-like interface for team prompt testing and daily interactions.

---

## 5. Development & IaC Workflow

* **Version Control:** All code, prompts, and documentation live in the `it-ops-library` GitHub repository.
* **Provisioning:** Terraform (OpenTofu) is the exclusive method for spinning up VMs and LXCs. No manual GUI creation is permitted for production nodes.
* **Agentic Coding:** **Claude Code** (`claude --yes`) is utilized via VS Code terminal, leveraging Model Context Protocol (MCP) to read the repository and execute infrastructure changes automatically.
* **Secrets:** All API keys and passwords are managed via `$env:TF_VAR_` environment variables or written to local `.gitignore` logs (`provisioning_logs.txt`).

---

## Current Build Status: Phase 2 (IaC Migration)
* [x] Establish 4-node Proxmox Cluster.
* [x] Connect TrueNAS NFS storage.
* [x] Upload base ISOs (Ubuntu, Windows Server, VirtIO) to NFS.
* [ ] Execute Terraform apply for pve02 (Ubuntu Docker + RTX A4500 Passthrough).
* [ ] Execute Terraform apply for pve03 (Windows Server + VirtIO drivers).
* [ ] Deploy AI inference stack (Ollama + Open WebUI).