resource "proxmox_lxc" "pihole" {
  target_node  = "pve01"
  hostname     = "pihole-dns"
  ostemplate   = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  password     = var.lxc_root_password
  unprivileged = true
  cores        = 1
  memory       = 512
  swap         = 512
  start        = true

  rootfs {
    storage = "local-lvm"
    size    = "8G"
  }

  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "dhcp"
  }
}