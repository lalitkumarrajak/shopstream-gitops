locals {
  labels = merge({
    "app.kubernetes.io/part-of" = "shopstream"
    "cluster"                   = var.cluster_name
    "managed-by"                = "terraform"
  }, var.labels)

  control_plane_private_ip = cidrhost(var.subnet_cidr, 10)
}

resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "hcloud_ssh_key" "admin" {
  name       = "${var.cluster_name}-admin"
  public_key = var.ssh_public_key
  labels     = local.labels
}

# --- networking --------------------------------------------------------------------------

resource "hcloud_network" "cluster" {
  name     = "${var.cluster_name}-net"
  ip_range = var.network_cidr
  labels   = local.labels
}

resource "hcloud_network_subnet" "nodes" {
  network_id   = hcloud_network.cluster.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_cidr
}

resource "hcloud_firewall" "nodes" {
  name   = "${var.cluster_name}-nodes"
  labels = local.labels

  dynamic "rule" {
    for_each = length(var.allowed_ssh_cidrs) > 0 ? [1] : []
    content {
      description = "SSH from admin networks"
      direction   = "in"
      protocol    = "tcp"
      port        = "22"
      source_ips  = var.allowed_ssh_cidrs
    }
  }

  dynamic "rule" {
    for_each = length(var.allowed_api_cidrs) > 0 ? [1] : []
    content {
      description = "Kubernetes API from admin networks"
      direction   = "in"
      protocol    = "tcp"
      port        = "6443"
      source_ips  = var.allowed_api_cidrs
    }
  }

  rule {
    description = "ICMP"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_placement_group" "spread" {
  name   = "${var.cluster_name}-spread"
  type   = "spread"
  labels = local.labels
}

# --- k3s server ----------------------------------------------------------------------------

resource "hcloud_server" "control_plane" {
  name               = "${var.cluster_name}-cp-1"
  server_type        = var.control_plane_type
  image              = var.image
  location           = var.location
  ssh_keys           = [hcloud_ssh_key.admin.id]
  firewall_ids       = [hcloud_firewall.nodes.id]
  placement_group_id = hcloud_placement_group.spread.id
  labels             = merge(local.labels, { role = "control-plane" })

  user_data = templatefile("${path.module}/templates/control-plane.yaml.tftpl", {
    k3s_token   = random_password.k3s_token.result
    k3s_channel = var.k3s_channel
    private_ip  = local.control_plane_private_ip
    cluster     = var.cluster_name
  })

  network {
    network_id = hcloud_network.cluster.id
    ip         = local.control_plane_private_ip
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  depends_on = [hcloud_network_subnet.nodes]

  lifecycle {
    ignore_changes = [user_data, image]
  }
}

# --- k3s agents ----------------------------------------------------------------------------

resource "hcloud_server" "worker" {
  count              = var.worker_count
  name               = "${var.cluster_name}-worker-${count.index + 1}"
  server_type        = var.worker_type
  image              = var.image
  location           = var.location
  ssh_keys           = [hcloud_ssh_key.admin.id]
  firewall_ids       = [hcloud_firewall.nodes.id]
  placement_group_id = hcloud_placement_group.spread.id
  labels             = merge(local.labels, { role = "worker" })

  user_data = templatefile("${path.module}/templates/worker.yaml.tftpl", {
    k3s_token   = random_password.k3s_token.result
    k3s_channel = var.k3s_channel
    server_url  = "https://${local.control_plane_private_ip}:6443"
  })

  network {
    network_id = hcloud_network.cluster.id
    ip         = cidrhost(var.subnet_cidr, 20 + count.index)
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  depends_on = [hcloud_server.control_plane]

  lifecycle {
    ignore_changes = [user_data, image]
  }
}

# --- ingress load balancer -------------------------------------------------------------------
# ingress-nginx runs as a NodePort Service on the workers (see README); the LB fronts it
# over the private network, so the nodes need no public HTTP exposure.

resource "hcloud_load_balancer" "ingress" {
  name               = "${var.cluster_name}-ingress"
  load_balancer_type = "lb11"
  location           = var.location
  labels             = local.labels
}

resource "hcloud_load_balancer_network" "ingress" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  network_id       = hcloud_network.cluster.id
  depends_on       = [hcloud_network_subnet.nodes]
}

resource "hcloud_load_balancer_target" "workers" {
  type             = "label_selector"
  load_balancer_id = hcloud_load_balancer.ingress.id
  label_selector   = "cluster=${var.cluster_name},role=worker"
  use_private_ip   = true
  depends_on       = [hcloud_load_balancer_network.ingress]
}

resource "hcloud_load_balancer_service" "http" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = var.ingress_node_ports.http
  proxyprotocol    = false

  health_check {
    protocol = "tcp"
    port     = var.ingress_node_ports.http
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

resource "hcloud_load_balancer_service" "https" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = var.ingress_node_ports.https
  proxyprotocol    = false

  health_check {
    protocol = "tcp"
    port     = var.ingress_node_ports.https
    interval = 10
    timeout  = 5
    retries  = 3
  }
}
