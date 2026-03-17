# VM Rebuild Report — ubuntu-docker
**Timestamp:** 2026-03-15 16:11:26 (Sun, Mar 15 2026)
**VM:** proxmox_vm_qemu.ubuntu_docker (VMID 100, pve02 @ 192.168.4.11)
**Operator:** Claude Code (automated rebuild workflow)
**Log file:** VM_REBUILD_LOG_20260315_161126.txt

---

## Phase 1: Destruction
- qm stop 100: ✅ (API POST /nodes/pve02/qemu/100/status/stop — VM transitioned to `stopped`)
- qm destroy 100: ✅ (API DELETE with purge=1 — UPID task completed; config file absent on verify)
- qm list (VMID 100 absent): ✅ (pve02 VM list shows only template 9002; VMID 100 config returns 500)

**Note:** SSH key (~/.ssh/id_ed25519) is passphrase-protected and no ssh-agent is running in this
shell (Git for Windows Bash). All Phase 1 operations were performed via the Proxmox REST API
using the `root@pam!terraform-builder` token.

---

## Phase 2: Terraform Rebuild
- terraform apply -replace: ✅
- Plan: **1 added, 0 changed, 0 destroyed**
- VM created: `pve02/qemu/100` (id confirmed)
- Terraform output: `docker_host_ip = "192.168.4.20"`
- Warning: "State drift detected: Resource was deleted outside Terraform" — **expected** (deliberate destroy in Phase 1)
- Cloud-init config confirmed via API: ubuntu user, SSH key injected, cipassword set, nameserver 1.1.1.1

---

## Phase 3: Network Verification
- VM running on pve02: ✅ (status: running, uptime ~346s at check time)
- IP config applied: ✅ (ipconfig0: `192.168.4.20/22`, gw: `192.168.4.1`)
- Ping 192.168.4.20 from workstation: ❌ ("Destination host unreachable" from 192.168.5.153)
- SSH ubuntu@192.168.4.20 from workstation: ❌ (TCP connection timeout)
- Static IP confirmed (via Proxmox config): ✅

**Root cause:** This workstation is on the `192.168.5.x` subnet. The VM is on `192.168.4.x`. The
Proxmox management API (port 8006) is accessible from this subnet, but general VM traffic (SSH
port 22 to 192.168.4.20) is not routed. pve02's SSH (192.168.4.11:22) is TCP-reachable but
requires the key passphrase.

---

## Phase 4: qemu-guest-agent
- Installed: ❌ (blocked — cannot SSH to 192.168.4.20 from this workstation)
- Service running: ❌ (confirmed via API: "QEMU guest agent is not running")

**Action required:** SSH to `ubuntu@192.168.4.20` from a host with network access to 192.168.4.x,
then run:
```bash
sudo apt-get update -qq
sudo apt-get install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
sudo systemctl status qemu-guest-agent --no-pager
```

---

## Phase 5: SSH Key Deployment
- ssh-copy-id: ❌ (blocked — routing gap from workstation to 192.168.4.x)
- Passwordless SSH test: ❌ (cannot test)

**Note:** The SSH public key IS already injected via cloud-init (`sshkeys` confirmed in Proxmox
cloud-init config). Once network routing is available, passwordless SSH should work — assuming
the private key passphrase is entered or an ssh-agent is running with the key loaded.

**Action required:** From a host on the 192.168.4.x network (or with a route), run:
```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@192.168.4.20 'hostname'
```

---

## Success Criteria
- [x] VM destroyed and recreated
- [ ] Ping to 192.168.4.20 (blocked by subnet routing from workstation)
- [ ] SSH to ubuntu@192.168.4.20 (blocked — routing + key passphrase)
- [ ] qemu-guest-agent installed and running (blocked — SSH required)
- [ ] VM shows IP in Proxmox UI (requires guest agent — not yet installed)

---

## Errors / Notes

### Blocker 1: SSH Key Passphrase
- `~/.ssh/id_ed25519` is passphrase-protected
- Shell is Git for Windows Bash with no ssh-agent running
- `BatchMode=yes` fails with `Permission denied (publickey,password)`
- **Fix:** Run `ssh-add ~/.ssh/id_ed25519` in a terminal with the passphrase before future automation

### Blocker 2: Subnet Routing Gap
- Workstation IP: `192.168.5.153`
- VM IP: `192.168.4.20`
- Proxmox management API (`192.168.4.10:8006`) IS reachable — likely VLAN ACL allows port 8006
- VM SSH (`192.168.4.20:22`) and ICMP are not routed to/from 192.168.5.x
- **Fix:** Add a static route on the workstation, use Tailscale/VPN, or run SSH steps from a host
  already on the 192.168.4.x network (e.g., log into pve01 or pve02 and SSH from there)

### Workaround Used
- All VM management (stop, destroy, verify, config check) performed via Proxmox REST API
- Terraform used its own API token for rebuild (no SSH dependency)
- VM creation verified via API: running state, correct IP config, cloud-init settings confirmed

---

## Next Steps
1. **Unlock SSH access:** On the workstation, run `eval $(ssh-agent) && ssh-add ~/.ssh/id_ed25519`
   and enter the passphrase. Then retry SSH to verify connectivity from a machine on 192.168.4.x.
2. **Install qemu-guest-agent:** SSH to `ubuntu@192.168.4.20` and run the apt install block above.
3. **Verify guest agent:** Check Proxmox UI — VM should show IP address once agent is running.
4. **Install Docker:**
   ```bash
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker ubuntu
   ```
5. **Deploy Ollama + Open WebUI via docker-compose.**
6. **Add static route (optional):** `route add 192.168.4.0 mask 255.255.252.0 192.168.4.1` to
   allow direct workstation access to the VM subnet without needing a jump host.
