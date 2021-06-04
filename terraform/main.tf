# main resource group
resource "azurerm_resource_group" "resource_group" {
    name     = "${var.name_prefix}-rg"
    location = var.location
}

# vnet 10.0.0.0/16
resource "azurerm_virtual_network" "vnet" {
    name                = "${var.name_prefix}-vnet"
    address_space       = var.vnet_address_space
    location            = azurerm_resource_group.resource_group.location
    resource_group_name = azurerm_resource_group.resource_group.name
}

# main subnet 10.0.0.0/24
resource "azurerm_subnet" "internal" {
    name                 = "${var.name_prefix}-subnet"
    resource_group_name  = azurerm_resource_group.resource_group.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = var.subnet_address_prefixes
}

# DC public ip
resource "azurerm_public_ip" "dc_public_ip" {
    name                = "${var.name_prefix}-dc-public-ip"
    resource_group_name = azurerm_resource_group.resource_group.name
    location            = azurerm_resource_group.resource_group.location
    allocation_method   = "Dynamic"
}

# DC NIC
resource "azurerm_network_interface" "dc_nic" {
    name                = "${var.name_prefix}-dc-nic"
    location            = azurerm_resource_group.resource_group.location
    resource_group_name = azurerm_resource_group.resource_group.name

    ip_configuration {
        name                          = "static_ip"
        subnet_id                     = azurerm_subnet.internal.id
        private_ip_address_allocation = "static"
        private_ip_address            = cidrhost(var.subnet_main, 10)
        public_ip_address_id = azurerm_public_ip.dc_public_ip.id
    }
}

# DC NSG
# TODO: enable JIT, maybe using local-exec provisioner and azure powershell
resource "azurerm_network_security_group" "dc_nsg" {
    name                = "${var.name_prefix}-dc-nsg"
    location            = azurerm_resource_group.resource_group.location
    resource_group_name = azurerm_resource_group.resource_group.name

    # RDP, currently allows all, should enable JIT
    # TODO: Enable JIT
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
    # TODO: Remove this security rule after provisioning
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
    subnet_id                 = azurerm_subnet.internal.id
    network_security_group_id = azurerm_network_security_group.dc_nsg.id
}

resource "azurerm_virtual_machine" "dc" {
    name                  = "${var.name_prefix}-dc"
    location              = azurerm_resource_group.resource_group.location
    resource_group_name   = azurerm_resource_group.resource_group.name
    network_interface_ids = [azurerm_network_interface.dc_nic.id]
    vm_size               = "Standard_B2ms"

    # Clean Image
    storage_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2019-Datacenter"
        version   = "latest"
    }

    # Disk
    delete_os_disk_on_termination = true
    storage_os_disk {
        name          = "${var.name_prefix}-dc-os-disk"
        create_option = "FromImage"
    }

    os_profile {
        computer_name  = "DC01"
        admin_username = var.admin_username
        admin_password = var.admin_password
    }

    os_profile_windows_config {
      # Enable WinRM for ansible
      winrm {
          protocol = "HTTP"
      }
    }

    tags = {
        type = "dc"
    }

    # enable jit
    provisioner "local-exec" {
        command = "bash ../enable_jit.sh \"${self.resource_group_name}\" \"${var.name_prefix}-jit\""
    }

    # change the dynamic ansible inventory to target the new resource group
    provisioner "local-exec" {
        command = "sed s/\"- .*#CHANGETHIS\"/\"- ${self.resource_group_name} #CHANGETHIS\"/ ../ansible/inventory_azure.yml"
    }

    # run the ansible playbook to configure the DC
    # TODO: This exposes the password to the machine running tf/ansible. might want to set this up using env vars
    #provisioner "local-exec" {
    #    command = "ansible-playbook ../ansible/dc_playbook.yml --user ${var.admin_username} -e admin_username ${var.admin_username} -e admin_password ${var.admin_password} -e domain_name ${var.domain_name}"
    #}
}