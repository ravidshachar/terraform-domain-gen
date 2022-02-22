data "http" "outgoing_ip" {
  url = "https://ifconfig.me"
}

data "azurerm_storage_account" "iacsa" {
  name                = var.dsc_sa
  resource_group_name = var.dsc_sa_rg
}

data "azurerm_storage_account_sas" "iacsa_sas" {
  connection_string = data.azurerm_storage_account.iacsa.primary_connection_string
  https_only        = true
  signed_version    = "2017-07-29"

  resource_types {
    service   = true
    container = false
    object    = false
  }

  services {
    blob      = true
    queue     = false
    table     = false
    file      = false
  }

  start  = timestamp()
  expiry = timeadd(timestamp(), "2h")

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
  }
}

locals {
  # local public ip
  outgoing_ip = chomp(data.http.outgoing_ip.body)
  repo_path   = abspath(format("%s/..", path.module))
  # this formats the prefix_to_domain_name variable to a string that can later be parsed by ansible extra vars
  prefix_to_domain_string = jsonencode({ "domain_names" = var.prefix_to_domain_name })
  # this creates a list of maps for each workstation. each workstation has a name_prefix and index value.
  # this will later be the value for the for_each map used in workstations.tf
  workstations_set = [for pair in setproduct(keys(var.prefix_to_domain_name), range(1, var.workstations_count + 1)) : {
    name_prefix = pair[0]
    index       = pair[1]
  }]
  exchange_set = var.deploy_exchange ? var.prefix_to_domain_name : {}
  adfs_set     = var.deploy_adfs ? var.prefix_to_domain_name : {}
  # this object maps azure name prefixes to the private ip of the dc
  # in that rg
  domain_to_ips = jsonencode({
    "dc_ips" = { for prefix in keys(var.prefix_to_domain_name) :
    prefix => azurerm_network_interface.dc_nic[prefix].private_ip_address }
  })
}
