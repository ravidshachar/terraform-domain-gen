# public ip for the first workstation
resource "azurerm_public_ip" "workstation_ip" {
    name                = "workstation1-public-ip"
    location            = azurerm_resource_group.resource_group.location
    resource_group_name = azurerm_resource_group.resource_group.name
    allocation_method   = "Dynamic"
}

# a nic per workstation
resource "azurerm_network_interface" "workstation_nic" {
    count = var.workstations_count

    name                = "${var.name_prefix}-workstation${count.index+1}-nic"
    location            = azurerm_resource_group.resource_group.location
    resource_group_name = azurerm_resource_group.resource_group.name

    ip_configuration {
      name = "static_ip"
      subnet_id = azurerm_subnet.internal.id
      private_ip_address_allocation = "static"
      private_ip_address = cidrhost(var.subnet_main, 11 + count.index)
      public_ip_address_id = count.index == 0 ? azurerm_public_ip.workstation_ip.id : ""
    }
}

resource "azurerm_windows_virtual_machine" "workstation" {
    count = var.workstations_count

    name                  = "${var.name_prefix}-workstation${count.index}"
    resource_group_name   = azurerm_resource_group.resource_group.name
    location              = azurerm_resource_group.resource_group.location
    network_interface_ids = [azurerm_network_interface.workstation_nic[count.index].id]
    size                  = "Standard_B2s"
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
      name                 = "workstation${count.index+1}-os-disk"
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

resource "null_resource" "workstation_playbook" {
    depends_on = [
        azurerm_windows_virtual_machine.workstation,
        null_resource.dc_playbook
    ]

    # init jit WinRM access for ansible
    provisioner "local-exec" {
        command = "bash ../init_jit_winrm.sh \"${azurerm_resource_group.resource_group.name}\" \"${var.name_prefix}-jit\" \"${join(" ", azurerm_windows_virtual_machine.workstation[*].name)}\""
    }

    provisioner "local-exec" {
        command = "ADMIN_PASSWORD=${var.admin_password}"
    }

    provisioner "local-exec" {
        command = "ansible-playbook ../ansible/workstations.yml --inventory ../ansible/inventory_azure_rm.yml --user=${var.admin_username} -e admin_username=${var.admin_username} -e ansible_winrm_password=$ADMIN_PASSWORD -e domain_name=${var.domain_name}"
    }
}