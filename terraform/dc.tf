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
resource "azurerm_network_security_group" "dc_nsg" {
    name                = "${var.name_prefix}-dc-nsg"
    location            = azurerm_resource_group.resource_group.location
    resource_group_name = azurerm_resource_group.resource_group.name

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
    subnet_id                 = azurerm_subnet.internal.id
    network_security_group_id = azurerm_network_security_group.dc_nsg.id
}

resource "azurerm_windows_virtual_machine" "dc" {
    name                  = "${var.name_prefix}-dc"
    location              = azurerm_resource_group.resource_group.location
    resource_group_name   = azurerm_resource_group.resource_group.name
    network_interface_ids = [azurerm_network_interface.dc_nic.id]
    size               = "Standard_A4_v2"
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
        name                 = "${var.name_prefix}-dc-os-disk"
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

resource "time_sleep" "wait_for_vm_creation" {
  depends_on = [
        azurerm_windows_virtual_machine.dc,
        azurerm_windows_virtual_machine.workstation
    ]

  create_duration = "10s"
}

resource "null_resource" "enable_jit" {
    depends_on = [
        time_sleep.wait_for_vm_creation
    ]

    # enable jit
    provisioner "local-exec" {
        command = "bash ../enable_jit.sh \"${azurerm_resource_group.resource_group.name}\" \"${var.name_prefix}-jit\""
    }
}

resource "null_resource" "init_jit_dc" {
    depends_on = [
        null_resource.enable_jit
    ]

    # init jit WinRM access for ansible
    provisioner "local-exec" {
        command = "bash ../init_jit_winrm.sh ${azurerm_resource_group.resource_group.name} ${var.name_prefix}-jit ${azurerm_windows_virtual_machine.dc.name}"
    }
}

resource "null_resource" "dc_playbook" {
    depends_on = [
        azurerm_windows_virtual_machine.dc,
        azurerm_windows_virtual_machine.workstation,
        null_resource.init_jit_dc
    ]

    # change the dynamic ansible inventory to target the new resource group
    provisioner "local-exec" {
        command = "sed -i s/\"- .*#CHANGETHIS\"/\"- ${azurerm_resource_group.resource_group.name} #CHANGETHIS\"/ ../ansible/inventory_azure_rm.yml"
    }

    # enter the password to a local file so we can use it without suppressing output
    provisioner "local-exec" {
        command = "echo ${var.admin_password} > .secret"
    }

    # run the ansible playbook to configure the DC
    # setup the password from a file so we can see the output properly
    provisioner "local-exec" {
        command = "ADMIN_PASSWORD=$(cat .secret); ansible-playbook ../ansible/dc_playbook.yml --inventory=../ansible/inventory_azure_rm.yml --user=${var.admin_username} -e admin_username=${var.admin_username} -e ansible_winrm_password=$ADMIN_PASSWORD -e domain_name=${var.domain_name}"
    }
}
