resource "macaddress" "instance_net0_mac" {
}

resource "consul_node" "consul_node_dns" {
  address = cidrhost(var.net0_network_cidr, local.ip_offset)
  name    = local.instance_name
  meta = {
    "external-node" : "true",
    "external-probe" : "true"
  }
}

resource "consul_service" "consul_service_ssh" {
  name    = "${local.instance_name}-ssh"
  address = cidrhost(var.net0_network_cidr, local.ip_offset)
  node    = consul_node.consul_node_dns.name
  port    = 22

  check {
    check_id                          = "${local.instance_name}:ssh"
    name                              = "SSH TCP on port 22"
    tcp                               = "${cidrhost(var.net0_network_cidr, local.ip_offset)}:22"
    interval                          = "10s"
    timeout                           = "5s"
    deregister_critical_service_after = "300s"
  }
}

module "instance_cloudinit_template" {
  source = "github.com/glitchcrab/terraform-module-proxmox-cloudinit-template"

  conn_type    = var.connection_type
  conn_user    = data.vault_generic_secret.terraform_pve_ssh.data["user"]
  conn_ssh_key = data.vault_generic_secret.terraform_pve_ssh.data["ssh-priv-key"]
  conn_target  = local.pm_host_address

  instance_name = "${local.instance_name}.${var.instance_domain}"

  snippet_root_dir  = local.snippet_root_dir
  snippet_dir       = local.snippet_dir
  snippet_file_base = replace("${local.instance_name}-${var.instance_domain}", ".", "-")

  primary_network = {
    gateway = local.primary_ip_gateway
    ip      = cidrhost(var.net0_network_cidr, local.ip_offset)
    macaddr = upper(macaddress.instance_net0_mac.address)
    netmask = var.net0_network_netmask
  }

  search_domains = var.search_domains
  dns_servers    = var.dns_servers

  user_data_blob = yamlencode({
    hostname : "${local.instance_name}.${var.instance_domain}"
  })
}

module "instance" {
  source     = "github.com/glitchcrab/terraform-module-proxmox-instance"
  depends_on = [module.instance_cloudinit_template]

  pve_instance_name        = "${local.instance_name}.${var.instance_domain}"
  pve_instance_description = var.instance_description
  vmid                     = local.vmid

  clone      = var.clone
  full_clone = var.full_clone
  qemu_agent = var.qemu_agent

  target_node   = var.target_node
  resource_pool = var.resource_pool

  cores   = var.resource_cpu_cores
  sockets = var.resource_cpu_sockets
  memory  = var.resource_memory
  boot    = var.boot

  network_interfaces = [{
    model   = var.network_model
    bridge  = var.net0_network_bridge
    tag     = var.net0_vlan_tag
    macaddr = upper(macaddress.instance_net0_mac.address)
  }]

  disks = [{
    type    = var.primary_disk_type
    storage = var.primary_disk_location
    size    = var.primary_disk_size
  }]

  snippet_dir             = local.snippet_dir
  snippet_file_base       = replace("${local.instance_name}-${var.instance_domain}", ".", "-")
  os_type                 = var.os_type
  cloudinit_cdrom_storage = var.cloudinit_cdrom_storage
  citemplate_storage      = var.citemplate_storage

  instance_domain = var.instance_domain
  searchdomain    = var.searchdomain
  nameserver      = var.nameserver
}
