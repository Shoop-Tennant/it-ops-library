variable "docker_vm_template" {
  description = "Name of the Cloud-Init VM template on Proxmox to clone for the Docker host"
  type        = string
  default     = "ubuntu-2404-cloud"
}

variable "docker_vm_ci_user" {
  description = "Cloud-Init username for the Docker VM"
  type        = string
  default     = "ubuntu"
}

variable "docker_vm_ci_password" {
  description = "Cloud-Init password for the Docker VM"
  type        = string
  sensitive   = true
}

variable "docker_vm_ssh_public_key" {
  description = "SSH public key to inject into the Docker VM via Cloud-Init"
  type        = string
  sensitive   = true
}

variable "ai_node_template" {
  description = "Name of the Cloud-Init VM template on Proxmox to clone for the AI node"
  type        = string
  default     = "ubuntu-2404-cloud"
}

variable "ai_node_ci_user" {
  description = "Cloud-Init username for the AI node VM"
  type        = string
  default     = "ubuntu"
}

variable "ai_node_ci_password" {
  description = "Cloud-Init password for the AI node VM"
  type        = string
  sensitive   = true
}

variable "lxc_root_password" {
  description = "Root password for the LXC containers"
  type        = string
  sensitive   = true
}

variable "proxmox_api_url" {
  description = "The API endpoint for Proxmox"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "The ID of the Proxmox API token"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "The secret of the Proxmox API token"
  type        = string
  sensitive   = true
}