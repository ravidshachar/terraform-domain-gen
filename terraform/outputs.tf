output "domain_controller_public_ip" {
  value = tomap({
    for name_prefix, domain_name in var.prefix_to_domain_name :
    domain_name => azurerm_public_ip.dc_public_ip[name_prefix].ip_address
  })
}

output "workstations_public_ip" {
  value = tomap({
    for combo in local.workstations_set :
    "${combo.name_prefix}-ws${combo.index}" => azurerm_public_ip.workstation_ip["${combo.name_prefix}.${combo.index}"].ip_address
  })
}

output "rgs_string" {
  value = join(",", keys(var.prefix_to_domain_name))
}

output "prefix_to_domain_name" {
  value = local.prefix_to_domain_name
}

output "domain_to_ips" {
  value = local.domain_to_ips
}