# Terraform Azure Domain Gen
## Overview
Small project I created to learn terraform and how it interacts with azure and ansible.
This project creates a new resource group with a domain controller, and as many workstations as you choose. also enables a JIT policy.
You should run this on a bash shell which is logged onto azure (using `az login` command in azure CLI)  
There are a few variables you can set to customize the deployment, you can see them in the `variables.tf` file. The important ones include:  
* prefix_to_domain_name - maps azure name prefixes to desired domain name (default: {ad-lab = "test.lab"})
* location - location to create all resource in (default: West Europe)
* dc_size - defines the size for the domain controllers (default: Standard_A4_v2)  
* ws_size - defines the size for the workstations (default: Standard_A2_v2)  
* vnet_address_space - defines the TOTAL address space. currently only the default is supported. each vnet gets a unique /16 address space, each subnet gets /24 address space (default: 10.0.0.0/8)  
* admin_username - domain admin username (default: domainadmin)
* domain_password - domain admin password (REQUIRED)
* workstations_count - amount of workstations desired (default: 1)  
## How to use?
Use a bash shell with azure CLI, terraform and ansible installed.  
You should also have python installed with the requirements described in requirements.txt. I recommend using a venv and running `pip install -r requirements.txt` to easily install all dependencies.  
create a .tfvars with the above variables, and then:
```
az login
terraform init
terraform apply -var-file <name>.tfvars
```
