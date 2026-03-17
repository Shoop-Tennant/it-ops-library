output "pihole_ip" {
  description = "Static IP assigned to the pihole-dns LXC container"
  value       = "192.168.4.2"
}

output "docker_host_ip" {
  description = "Static IP assigned to the ubuntu-docker VM"
  value       = "192.168.4.20"
}

output "ai_node_ip" {
  description = "Static IP assigned to the ai-node-a4500 VM"
  value       = "192.168.4.15"
}

output "proxmox_nodes" {
  description = "All Proxmox cluster node names"
  value       = ["pve01", "pve02", "pve03", "pve04"]
}
