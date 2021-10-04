# public ip per exchange server
resource "azurerm_public_ip" "exchange_ip" {
  for_each = var.prefix_to_domain_name

  name                = "${each.key}-ex-public-ip"
  resource_group_name = azurerm_resource_group.resource_group[each.key].name
  location            = azurerm_resource_group.resource_group[each.key].location
  allocation_method   = "Dynamic"
}

# Exchange NIC
resource "azurerm_network_interface" "ex_nic" {
  for_each = var.prefix_to_domain_name

  name                = "${each.key}-ex-nic"
  location            = azurerm_resource_group.resource_group[each.key].location
  resource_group_name = azurerm_resource_group.resource_group[each.key].name

  ip_configuration {
    name                          = "static_ip"
    subnet_id                     = azurerm_subnet.internal[each.key].id
    private_ip_address_allocation = "static"
    private_ip_address            = cidrhost(azurerm_subnet.internal[each.key].address_prefixes[0], 20)
    public_ip_address_id          = azurerm_public_ip.exchange_ip[each.key].id
  }
}

resource "azurerm_windows_virtual_machine" "exchange" {
  for_each = var.prefix_to_domain_name

  name                  = "${each.key}-ex"
  resource_group_name   = azurerm_resource_group.resource_group[each.key].name
  location              = azurerm_resource_group.resource_group[each.key].location
  network_interface_ids = [azurerm_network_interface.ex_nic[each.key].id]
  size                  = var.ex_size
  admin_username        = "localadmin"
  admin_password        = var.admin_password
  priority              = "Spot"
  eviction_policy       = "Deallocate"

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  os_disk {
    name                 = "${each.key}-ex-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Enable WinRM for ansible
  winrm_listener {
    protocol = "Http"
  }

  tags = {
    type = "exchange"
  }
}

resource "null_resource" "init_jit_ex" {
  for_each = var.prefix_to_domain_name
  # let it run only after exchange servers are provisioned and the domain is ready
  depends_on = [
    azurerm_windows_virtual_machine.exchange,
    null_resource.dc_playbook
  ]

  # init jit WinRM access for ansible
  provisioner "local-exec" {
    command = "bash ${local.repo_path}/init_jit_winrm.sh ${azurerm_resource_group.resource_group[each.key].name} ${each.key}-jit ${azurerm_windows_virtual_machine.exchange[each.key].name}"
  }
}

resource "null_resource" "exchange_playbook" {

  # let it run only after jit is initiated for ws
  depends_on = [
    azurerm_windows_virtual_machine.exchange,
    null_resource.dc_playbook,
    null_resource.init_jit_ex
  ]

  # sleep 10 to allow jit to initialize
  provisioner "local-exec" {
    command = "sleep 10"
  }

  provisioner "local-exec" {
    command = "echo ${var.admin_password} > .secret"
  }

  # use a password from file so we can see the output properly
  provisioner "local-exec" {
    command = "ADMIN_PASSWORD=$(cat .secret); ansible-playbook ${local.repo_path}/ansible/exchange_playbook.yml --inventory=${local.repo_path}/ansible/inventory_azure_rm.yml --user=localadmin -e admin_username=${var.admin_username} -e ansible_winrm_password=$ADMIN_PASSWORD -e '${local.prefix_to_domain_string}' -e '${local.domain_to_ips}'"
  }

  # delete secret file
  provisioner "local-exec" {
    command = "rm .secret"
  }
}
