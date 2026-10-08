output "control_plane_ipv4" {
  description = "Public IPv4 of the k3s server."
  value       = hcloud_server.control_plane.ipv4_address
}

output "worker_ipv4" {
  description = "Public IPv4 addresses of the k3s agents."
  value       = hcloud_server.worker[*].ipv4_address
}

output "ingress_load_balancer_ipv4" {
  description = "Point your DNS records (e.g. shop.example.com) at this address."
  value       = hcloud_load_balancer.ingress.ipv4
}

output "kubeconfig_command" {
  description = "Fetches a kubeconfig for the new cluster."
  value       = "ssh root@${hcloud_server.control_plane.ipv4_address} 'cat /etc/rancher/k3s/k3s.yaml' | sed 's/127.0.0.1/${hcloud_server.control_plane.ipv4_address}/' > kubeconfig-${var.cluster_name}.yaml"
}
