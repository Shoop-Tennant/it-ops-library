# ubuntu-docker-vm.tf
# Deploys a full Ubuntu 24.04 VM (Cloud-Init) on Proxmox to act as a dedicated Docker host.
#
# PRE-REQUISITE — run these commands once on the Proxmox host shell (as root)
# before the first `terraform apply`:
#
#   # 1. Download the Ubuntu 24.04 cloud image
#   wget -O /var/lib/vz/template/iso/ubuntu-2404-cloud.img \
#     https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
#
#   # 2. Create a new VM to use as the template (ID 9000 — adjust if taken)
#   qm create 9000 --name ubuntu-2404-cloud --memory 1024 --cores 1 --net0 virtio,bridge=vmbr0
#
#   # 3. Import the cloud image as a disk
#   qm importdisk 9000 /var/lib/vz/template/iso/ubuntu-2404-cloud.img local-lvm
#
#   # 4. Attach the disk, add cloud-init drive, set boot order
#   qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
#   qm set 9000 --ide2 local-lvm:cloudinit
#   qm set 9000 --boot c --bootdisk scsi0
#   qm set 9000 --serial0 socket --vga serial0
#
#   # 5. Convert to template
#   qm template 9000
#
# The template name "ubuntu-2404-cloud" must match var.docker_vm_template below.

resource "proxmox_vm_qemu" "ubuntu_docker" {
  name        = "ubuntu-docker"
  description = "Dedicated Docker host - Ubuntu 24.04 Cloud-Init"
  target_node = "pve02"

  # Clone from the Cloud-Init template created in the pre-requisite steps above
  clone      = var.docker_vm_template
  full_clone = true

  # Guest agent — requires qemu-guest-agent installed inside the VM
  agent = 1

  os_type = "cloud-init"
  qemu_os = "l26"

  # CPU / Memory
  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }
  memory = 16384

  # Boot disk (50 GB) + Cloud-Init drive
  disks {
    virtio {
      virtio0 {
        disk {
          size       = 50
          storage    = "local-lvm"
          discard = true
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

  # Network
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud-Init: identity
  ciuser    = var.docker_vm_ci_user
  cipassword = var.docker_vm_ci_password
  sshkeys   = var.docker_vm_ssh_public_key

  # Cloud-Init: networking — swap to a static IP if preferred
  ipconfig0  = "ip=dhcp"
  nameserver = "1.1.1.1"

  # Start the VM automatically after provisioning
  vm_state = "running"
}
