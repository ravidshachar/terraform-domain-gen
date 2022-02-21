# main resource group
resource "azurerm_resource_group" "resource_group" {
  for_each = var.prefix_to_domain_name

  name     = "${each.key}-rg"
  location = var.location
}

# vnet 10.0.0.0/16 ->
resource "azurerm_virtual_network" "vnet" {
  for_each = var.prefix_to_domain_name

  name = "${each.key}-vnet"
  # Use this hack to get a unique vnet address space for every rg, should have a /16 address space 
  address_space       = [cidrsubnet(var.vnet_address_space, 8, index(keys(var.prefix_to_domain_name), each.key))]
  location            = azurerm_resource_group.resource_group[each.key].location
  resource_group_name = azurerm_resource_group.resource_group[each.key].name
  dns_servers         = [azurerm_network_interface.dc_nic[each.key].private_ip_address]
}

# main subnet 10.0.0.0/24
resource "azurerm_subnet" "internal" {
  for_each = var.prefix_to_domain_name

  name                 = "${each.key}-subnet"
  resource_group_name  = azurerm_resource_group.resource_group[each.key].name
  virtual_network_name = azurerm_virtual_network.vnet[each.key].name
  address_prefixes     = [cidrsubnet(azurerm_virtual_network.vnet[each.key].address_space[0], 8, 0)]
}

# DC public ip
resource "azurerm_public_ip" "dc_public_ip" {
  for_each = var.prefix_to_domain_name

  name                = "${each.key}-dc-public-ip"
  resource_group_name = azurerm_resource_group.resource_group[each.key].name
  location            = azurerm_resource_group.resource_group[each.key].location
  allocation_method   = "Dynamic"
}

# DC NIC
resource "azurerm_network_interface" "dc_nic" {
  for_each = var.prefix_to_domain_name

  name                = "${each.key}-dc-nic"
  location            = azurerm_resource_group.resource_group[each.key].location
  resource_group_name = azurerm_resource_group.resource_group[each.key].name

  ip_configuration {
    name                          = "static_ip"
    subnet_id                     = azurerm_subnet.internal[each.key].id
    private_ip_address_allocation = "static"
    private_ip_address            = cidrhost(azurerm_subnet.internal[each.key].address_prefixes[0], 10)
    public_ip_address_id          = azurerm_public_ip.dc_public_ip[each.key].id
  }
}

# DC NSG
resource "azurerm_network_security_group" "dc_nsg" {
  for_each = var.prefix_to_domain_name

  name                = "${each.key}-dc-nsg"
  location            = azurerm_resource_group.resource_group[each.key].location
  resource_group_name = azurerm_resource_group.resource_group[each.key].name

  # RDP, currently allows all, should enable JIT
  security_rule {
    name                       = "Allow RDP"
    priority                   = "1000"
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "TCP"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # WinRM for ansible, only to the ip associated with the terraform client.
  security_rule {
    name                       = "Allow WinRM"
    priority                   = "1001"
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "TCP"
    source_port_range          = "*"
    destination_port_range     = "5985"
    source_address_prefix      = "${local.outgoing_ip}/32"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "dc_assoc" {
  for_each = var.prefix_to_domain_name

  subnet_id                 = azurerm_subnet.internal[each.key].id
  network_security_group_id = azurerm_network_security_group.dc_nsg[each.key].id
}

resource "azurerm_windows_virtual_machine" "dc" {
  for_each = var.prefix_to_domain_name

  name                  = "${each.key}-dc"
  location              = azurerm_resource_group.resource_group[each.key].location
  resource_group_name   = azurerm_resource_group.resource_group[each.key].name
  network_interface_ids = [azurerm_network_interface.dc_nic[each.key].id]
  size                  = var.dc_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  priority              = "Spot"
  eviction_policy       = "Deallocate"

  # Clean Image
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  # Disk
  os_disk {
    name                 = "${each.key}-dc-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Enable WinRM for ansible
  winrm_listener {
    protocol = "Http"
  }

  tags = {
    type = "dc"
  }
}

resource "azurerm_virtual_machine_extension" "deploy_dc" {
  for_each = var.prefix_to_domain_name

  name                 = "deploy_dc"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc[each.key]
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.9"

  settings = <<SETTINGS
    {
      "Modulesurl": "${format("https://%s.blob.core.windows.net/%s/%s%s", var.dsc_sa, "deploy_ad.zip", "PrivateSettingsRef:configurationUrlSasToken")}",
      "ConfigurationFunction": "deploy_ad.ps1\\ad_setup",
      "properties": {
        "DomainName": "${each.value}",
        "AdminCreds": {
          "UserName": "${var.admin_username}",
          "Password": "PrivateSettingsRef:AdminPassword"
        }
      }
    }
  SETTINGS

  protected_settings = <<PROTECTED
    {
      "Items": {
        "configurationUrlSasToken": ${azurerm_storage_account_sas.iacsa_sas.sas},
        "AdminPassword": "${var.admin_password}"
      }
    }
  PROTECTED
}

#resource "time_sleep" "wait_for_vm_creation" {
#  depends_on = [
#    azurerm_windows_virtual_machine.dc,
#    azurerm_windows_virtual_machine.workstation,
#    azurerm_windows_virtual_machine.exchange
#  ]
#
#  create_duration = "30s"
#}
#
#resource "null_resource" "enable_jit" {
#  for_each = var.prefix_to_domain_name
#  depends_on = [
#    time_sleep.wait_for_vm_creation
#  ]
#
#  # enable jit
#  provisioner "local-exec" {
#    command = "bash ${local.repo_path}/enable_jit.sh \"${azurerm_resource_group.resource_group[each.key].name}\" \"${each.key}-jit\""
#  }
#}
#
#resource "null_resource" "init_jit_dc" {
#  for_each = var.prefix_to_domain_name
#  depends_on = [
#    null_resource.enable_jit
#  ]
#
#  # init jit WinRM access for ansible
#  provisioner "local-exec" {
#    command = "bash ${local.repo_path}/init_jit_winrm.sh ${azurerm_resource_group.resource_group[each.key].name} ${each.key}-jit ${azurerm_windows_virtual_machine.dc[each.key].name}"
#  }
#}
#
#resource "null_resource" "dc_playbook" {
#  depends_on = [
#    azurerm_windows_virtual_machine.dc,
#    azurerm_windows_virtual_machine.workstation,
#    null_resource.init_jit_dc
#  ]
#
#  # sleep 10 to allow jit to initialize
#  provisioner "local-exec" {
#    command = "sleep 10"
#  }
#
#  # change the dynamic ansible inventory to target the new resource groups
#  provisioner "local-exec" {
#    command = "python '${local.repo_path}/edit_inventory.py' '${local.repo_path}/ansible/inventory_azure_rm.yml' ${join(",", keys(var.prefix_to_domain_name))}"
#  }
#
#  # enter the password to a local file so we can use it without suppressing output
#  provisioner "local-exec" {
#    command = "echo ${var.admin_password} > .secret"
#  }
#
#  # run the ansible playbook to configure the DC
#  # setup the password from a file so we can see the output properly
#  provisioner "local-exec" {
#    command = "ADMIN_PASSWORD=$(cat .secret); ansible-playbook ${local.repo_path}/ansible/dc_playbook.yml --inventory=${local.repo_path}/ansible/inventory_azure_rm.yml --user=${var.admin_username} -e admin_username=${var.admin_username} -e ansible_winrm_password=$ADMIN_PASSWORD -e '${local.prefix_to_domain_string}'"
#  }
#}
#