# ai-node-p4000.tf
# AI inference node — Ubuntu 24.04, Quadro P4000 GPU passthrough, hosted on pve01.
#
# PRE-REQUISITES on pve01 (verify before first apply):
#
#   # Confirm IOMMU is enabled (should see "DMAR: IOMMU enabled" or similar):
#   dmesg | grep -i iommu | head -5
#
#   # Confirm P4000 IOMMU group (should only contain 00:01.0 root port + 01:00.0 GPU + 01:00.1 audio):
#   ls /sys/bus/pci/devices/0000:01:00.0/iommu_group/devices/
#
#   # Confirm vfio-pci is bound to the GPU:
#   cat /sys/bus/pci/devices/0000:01:00.0/driver/module/drivers
#   # Should show: pci:vfio-pci
#
#   # Confirm VFIO modules loaded:
#   lsmod | grep vfio
#
# NOTE: q35 machine type required for PCIe passthrough.
# NOTE: GPU (hostpci0) is attached post-creation via pvesh in ai-node-p4000-deploy.sh
#       because the telmate/proxmox provider 3.0.2-rc07 cannot reliably set hostpci
#       on initial clone. GPU is added after VM creation with:
#         pvesh set /nodes/pve01/qemu/<id>/config --hostpci0 0000:01:00,pcie=1,rombar=1
#
# NOTE: Same virtio0 disk trick as a4500: provider creates empty virtio0, OS disk
#       survives as unused0, deploy script moves it back and resizes to 120G.

resource "proxmox_vm_qemu" "ai_node_p4000" {
  name        = "ai-node-p4000"
  description = "AI inference node — Quadro P4000 GPU passthrough, Ollama"
  target_node = "pve01"

  clone      = "ubuntu-2404-cloud"
  full_clone = true

  agent   = 1
  os_type = "cloud-init"
  qemu_os = "l26"

  # q35 required for PCIe passthrough
  machine = "q35"

  cpu {
    cores   = 8
    sockets = 1
    type    = "host"
  }
  memory = 24576

  # Serial console for qm terminal access
  serial {
    id   = 0
    type = "socket"
  }

  # No virtual display — GPU owns output once attached
  vga {
    type = "serial0"
  }

  # See note above: empty virtio0 placeholder, OS disk survives as unused0
  disks {
    virtio {
      virtio0 {
        disk {
          size    = 2
          storage = "local-lvm"
        }
      }
    }
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }

  boot = "order=virtio0"

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  ciuser     = var.ai_node_ci_user
  cipassword = var.ai_node_ci_password
  sshkeys    = var.docker_vm_ssh_public_key

  ipconfig0  = "ip=192.168.4.16/22,gw=192.168.4.1"
  nameserver = "1.1.1.1"

  vm_state = "running"

  lifecycle {
    ignore_changes = [
      hostpci,
      disk,
    ]
  }
}
