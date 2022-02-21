# public ip per workstation
resource "azurerm_public_ip" "workstation_ip" {
  # this sets a unique key in the convention of {name_prefix}.{index}, the value
  # contains the name prefix and index
  for_each = { for combo in local.workstations_set : "${combo.name_prefix}.${combo.index}" => combo }

  name                = "${each.value.name_prefix}ws${each.value.index}-public-ip"
  location            = azurerm_resource_group.resource_group[each.value.name_prefix].location
  resource_group_name = azurerm_resource_group.resource_group[each.value.name_prefix].name
  allocation_method   = "Dynamic"
}

# a nic per workstation
resource "azurerm_network_interface" "workstation_nic" {
  for_each = { for combo in local.workstations_set : "${combo.name_prefix}.${combo.index}" => combo }

  name                = "${each.value.name_prefix}-ws${each.value.index}-nic"
  location            = azurerm_resource_group.resource_group[each.value.name_prefix].location
  resource_group_name = azurerm_resource_group.resource_group[each.value.name_prefix].name

  ip_configuration {
    name                          = "static_ip"
    subnet_id                     = azurerm_subnet.internal[each.value.name_prefix].id
    private_ip_address_allocation = "static"
    private_ip_address            = cidrhost(azurerm_subnet.internal[each.value.name_prefix].address_prefixes[0], 10 + each.value.index)
    public_ip_address_id          = azurerm_public_ip.workstation_ip[each.key].id
  }
}

resource "azurerm_windows_virtual_machine" "workstation" {
  for_each = { for combo in local.workstations_set : "${combo.name_prefix}.${combo.index}" => combo }

  name                  = "${each.value.name_prefix}-ws${each.value.index}"
  resource_group_name   = azurerm_resource_group.resource_group[each.value.name_prefix].name
  location              = azurerm_resource_group.resource_group[each.value.name_prefix].location
  network_interface_ids = [azurerm_network_interface.workstation_nic[each.key].id]
  size                  = var.ws_size
  admin_username        = "localadmin"
  admin_password        = var.admin_password
  priority              = "Spot"
  eviction_policy       = "Deallocate"

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-10"
    sku       = "20h2-pro"
    version   = "latest"
  }

  os_disk {
    name                 = "${each.value.name_prefix}-ws${each.value.index}-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Enable WinRM for ansible
  winrm_listener {
    protocol = "Http"
  }

  tags = {
    type = "workstation"
  }
}

#resource "null_resource" "init_jit_ws" {
#  for_each = var.prefix_to_domain_name
#  # let it run only after workstations are provisioned and the domain is ready
#  depends_on = [
#    azurerm_windows_virtual_machine.workstation,
#    null_resource.dc_playbook
#  ]
#
#  # init jit WinRM access for ansible
#  provisioner "local-exec" {
#    command = "bash ${local.repo_path}/init_jit_winrm.sh ${azurerm_resource_group.resource_group[each.key].name} ${each.key}-jit ${join(" ", formatlist("%s-ws%s", each.key, range(1, var.workstations_count + 1)))}"
#  }
#}
#
#resource "null_resource" "workstation_playbook" {
#
#  # let it run only after jit is initiated for ws
#  depends_on = [
#    azurerm_windows_virtual_machine.workstation,
#    null_resource.dc_playbook,
#    null_resource.init_jit_ws
#  ]
#
#  # sleep 10 to allow jit to initialize
#  provisioner "local-exec" {
#    command = "sleep 10"
#  }
#
#  provisioner "local-exec" {
#    command = "echo ${var.admin_password} > .secret"
#  }
#
#  # use a password from file so we can see the output properly
#  provisioner "local-exec" {
#    command = "ADMIN_PASSWORD=$(cat .secret); ansible-playbook ${local.repo_path}/ansible/workstations_playbook.yml --inventory=${local.repo_path}/ansible/inventory_azure_rm.yml --user=localadmin -e admin_username=${var.admin_username} -e ansible_winrm_password=$ADMIN_PASSWORD -e '${local.prefix_to_domain_string}' -e '${local.domain_to_ips}'"
#  }
#
#  # delete secret file
#  provisioner "local-exec" {
#    command = "rm .secret"
#  }
#}
#