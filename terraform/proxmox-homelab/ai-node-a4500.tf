# ai-node-a4500.tf
# AI inference node — Ubuntu 24.04, RTX A4500 GPU passthrough, hosted on pve02.
#
# PRE-REQUISITES on pve02 (verify once before first apply):
#
#   # Confirm GPU is in IOMMU group 13 and vfio-bound:
#   find /sys/kernel/iommu_groups/13/devices/ -type l
#   # Expected: 0000:01:00.0 (GPU) and 0000:01:00.1 (audio)
#
#   # Confirm vfio-pci is loaded:
#   lsmod | grep vfio
#
#   # Confirm the GPU PCI IDs are in /etc/modprobe.d/vfio.conf:
#   cat /etc/modprobe.d/vfio.conf
#   # Should contain: options vfio-pci ids=10de:24ba,10de:228b
#
# NOTE: q35 machine type is required for PCIe passthrough.
# NOTE: The disk block uses scsi0 to match the template's disk slot — this
#       causes Terraform to resize the cloned disk rather than creating an
#       empty new disk (which would leave the OS disk as unused0).

resource "proxmox_vm_qemu" "ai_node_a4500" {
  name        = "ai-node-a4500"
  description = "AI inference node — RTX A4500 GPU passthrough, Ollama"
  target_node = "pve02"

  clone      = var.ai_node_template
  full_clone = true

  agent   = 1
  os_type = "cloud-init"
  qemu_os = "l26"

  # q35 is required for PCIe passthrough
  machine = "q35"

  cpu {
    cores   = 8
    sockets = 1
    type    = "host"
  }
  memory = 24576

  # RTX A4500 hostpci is attached post-creation via pvesh in ai-node-deploy.sh.
  # The telmate/proxmox provider 3.0.2-rc07 cannot set mapped PCI devices via
  # either the hostpci or pci block. GPU is added after VM creation with:
  #   pvesh set /nodes/pve02/qemu/<id>/config --hostpci0 mapping=rtx-a4500,pcie=1,rombar=1
  #
  # Serial console for qm terminal access
  serial {
    id   = 0
    type = "socket"
  }

  # No virtual display — GPU owns the output once attached
  vga {
    type = "serial0"
  }

  # Disk: virtio0 intentionally uses a DIFFERENT slot than the template (scsi0).
  # The telmate provider replaces any disk in the same slot as the clone's disk.
  # Using virtio0 causes the provider to create a new (initially empty) virtio0
  # while the cloned OS disk survives as unused0. ai-node-deploy.sh then:
  #   1. Stops the VM
  #   2. Deletes the empty virtio0
  #   3. Moves unused0 (OS) → virtio0
  #   4. Resizes to 120G
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

  ipconfig0  = "ip=192.168.4.15/22,gw=192.168.4.1"
  nameserver = "1.1.1.1"

  vm_state = "running"
}
