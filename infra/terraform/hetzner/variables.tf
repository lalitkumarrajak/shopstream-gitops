variable "hcloud_token" {
  description = "Hetzner Cloud API token (read/write). Pass via TF_VAR_hcloud_token, never commit it."
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "shopstream"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.cluster_name))
    error_message = "cluster_name must be 3-31 chars of lowercase letters, digits and dashes."
  }
}

variable "location" {
  description = "Hetzner location (nbg1, fsn1, hel1, ash, hil, sin)."
  type        = string
  default     = "nbg1"
}

variable "network_zone" {
  description = "Network zone matching the location (eu-central, us-east, us-west, ap-southeast)."
  type        = string
  default     = "eu-central"
}

variable "image" {
  description = "OS image for all nodes."
  type        = string
  default     = "ubuntu-24.04"
}

variable "control_plane_type" {
  description = "Server type for the k3s server node (check `hcloud server-type list`)."
  type        = string
  default     = "cx23"
}

variable "worker_type" {
  description = "Server type for k3s agent nodes."
  type        = string
  default     = "cx33"
}

variable "worker_count" {
  description = "Number of k3s agent nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 10
    error_message = "worker_count must be between 1 and 10."
  }
}

variable "k3s_channel" {
  description = "k3s release channel (stable, latest) or a pinned version like v1.33.5+k3s1."
  type        = string
  default     = "stable"
}

variable "ssh_public_key" {
  description = "Public key installed on every node."
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to reach SSH (22). Keep this to your own IP."
  type        = list(string)
  default     = []
}

variable "allowed_api_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API (6443)."
  type        = list(string)
  default     = []
}

variable "network_cidr" {
  description = "Private network range."
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet for the cluster nodes."
  type        = string
  default     = "10.10.1.0/24"
}

variable "ingress_node_ports" {
  description = "NodePorts of the ingress-nginx Service (http, https) targeted by the load balancer."
  type        = object({ http = number, https = number })
  default     = { http = 30080, https = 30443 }
}

variable "labels" {
  description = "Extra labels applied to every resource."
  type        = map(string)
  default     = {}
}
