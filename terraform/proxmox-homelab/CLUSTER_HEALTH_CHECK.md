# Cluster Health Check — Proxmox Homelab

**Date:** 2026-03-15
**Subnet Migration:** `/24` → `/22` complete
**Quorum:** 4/4 nodes voting ✅

---

## pvecm status (run on pve01: 192.168.4.10)

```
# Run: ssh root@192.168.4.10 pvecm status
```

> Paste output here after running. Expected: 4 nodes, quorate, all IPs in 192.168.4.x/22.

---

## /22 Network Verification

Confirm each node's management interface is on the `/22` subnet:

```bash
# Run on each node:
ip addr show vmbr0 | grep 'inet '
```

| Node | Expected IP/Prefix | Verified |
|:-----|:-------------------|:---------|
| pve01 | 192.168.4.10/22 | ☐ |
| pve02 | 192.168.4.11/22 | ☐ |
| pve03 | 192.168.4.12/22 | ☐ |
| pve04 | 192.168.4.13/22 | ☐ |

---

## Corosync Config Verification

```bash
# Run on pve01:
cat /etc/pve/corosync.conf
```

Key fields to verify:
- `nodeid` matches expected node order (1–4)
- All `ring0_addr` entries are in the `192.168.4.0/22` range
- `expected_votes: 4`
- `two_node: 0` (4-node cluster, no tie-break needed)

> Paste corosync.conf output here.

---

## Terraform API Connectivity

```bash
# Verify Terraform can reach pve01 API after IP migration:
curl -sk https://192.168.4.10:8006/api2/json/version | jq .data.version
```

Expected: Proxmox VE version string (e.g., `8.x.x`).

---

## Post-Migration Checklist

- [ ] `pvecm status` shows 4/4 nodes quorate
- [ ] All nodes reachable at new `.10–.13` IPs
- [ ] TrueNAS NFS mount still accessible from all nodes (`df -h | grep truenas`)
- [ ] Terraform `apply` succeeds against new API URL (`192.168.4.10:8006`)
- [ ] Tailscale MagicDNS updated with new node IPs
- [ ] `Homelab.md` node IP table updated to reflect post-migration IPs
