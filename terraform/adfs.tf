# public ip per adfs server
resource "azurerm_public_ip" "adfs_ip" {
    for_each = local.adfs_set

    name                = "${each.key}-adfs-public-ip"
    resource_group_name = azurerm_resource_group.resource_group[each.key].name
    location            = azurerm_resource_group.resource_group[each.key].location
    allocation_method = "Dynamic"
}

# ADFS NIC
resource "azurerm_network_interface" "adfs_nic" {
  for_each = local.adfs_set

  name                = "${each.key}-adfs-nic"
  location            = azurerm_resource_group.resource_group[each.key].location
  resource_group_name = azurerm_resource_group.resource_group[each.key].name

  ip_configuration {
    name                          = "static_ip"
    subnet_id                     = azurerm_subnet.internal[each.key].id
    private_ip_address_allocation = "static"
    private_ip_address            = cidrhost(azurerm_subnet.internal[each.key].address_prefixes[0], 30)
    public_ip_address_id          = azurerm_public_ip.adfs_ip[each.key].id
  }
}

resource "azurerm_windows_virtual_machine" "adfs" {
  for_each = local.adfs_set

  name                  = "${each.key}-adfs"
  resource_group_name   = azurerm_resource_group.resource_group[each.key].name
  location              = azurerm_resource_group.resource_group[each.key].location
  network_interface_ids = [azurerm_network_interface.adfs_nic[each.key].id]
  size                  = var.adfs_size
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
    name                 = "${each.key}-adfs-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Enable WinRM for ansible
  winrm_listener {
    protocol = "Http"
  }

  tags = {
    type = "adfs"
  }
}

resource "azurerm_virtual_machine_extension" "deploy_adfs" {
  for_each = local.adfs_set

  depends_on = [
    azurerm_virtual_machine_extension.deploy_dc
  ]

  name                 = "deploy_adfs"
  virtual_machine_id   = azurerm_windows_virtual_machine.adfs[each.key].id
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.77"

  settings = <<SETTINGS
    {
      "configuration": {
        "url": "${format("https://%s.blob.core.windows.net/%s/%s", var.dsc_sa, var.dsc_sa_container, var.dsc_adfs_archive_file)}",
        "script": "deploy_adfs.ps1",
        "function": "install_adfs" 
      },
      "configurationArguments": {
        "DomainName": "${each.value}",
        "FSName": "${each.key}-adfs.${each.value}"
      }
    }
  SETTINGS

  # "configurationUrlSasToken": "${data.azurerm_storage_account_sas.iacsa_sas.sas}",

  protected_settings = <<PROTECTED
    {
      "configurationArguments": {
        "AdminCreds": {
          "UserName": "${var.admin_username}",
          "Password": "${var.admin_password}"
        }
      }
    }
  PROTECTED
}