output "domain_controller_public_ip" {
    value = azurerm_public_ip.dc_public_ip.ip_address
}

output "workstations_public_ip" {
    value = azurerm_public_ip.workstation_ip.*.ip_address
}