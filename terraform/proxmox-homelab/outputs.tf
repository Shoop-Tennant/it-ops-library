output "pihole_ip" {
  description = "Static IP assigned to the pihole-dns LXC container"
  value       = "192.168.4.2"
}

output "docker_host_ip" {
  description = "Static IP assigned to the ubuntu-docker VM"
  value       = "192.168.4.20"
}

output "ai_node_a4500_ip" {
  description = "Static IP assigned to the ai-node-a4500 VM (RTX A4500, pve02)"
  value       = "192.168.4.15"
}

output "ai_node_p4000_ip" {
  description = "Static IP assigned to the ai-node-p4000 VM (Quadro P4000, pve01)"
  value       = "192.168.4.16"
}

output "proxmox_nodes" {
  description = "All Proxmox cluster node names"
  value       = ["pve01", "pve02", "pve03", "pve04"]
}
