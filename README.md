# Terraform Azure Domain Gen
## Overview
Small project I created to learn terraform and how it interacts with azure and ansible.
This project creates a new resource group with a domain controller, and as many workstations as you choose. also enables a JIT policy.
You should run this on a bash shell which is logged onto azure (using `az login` command in azure CLI)  
There are a few variables you can set to customize the deployment, you can see them in the `variables.tf` file. The important ones include:  
* name_prefix - the prefix for the resources names in Azure (default: ad-lab)
* location - location to create all resource in (default: West Europe)
* admin_username - domain admin username (default: domainadmin)
* domain_password - domain admin password (REQUIRED)
* domain_name - domain name (REQUIRED)
* workstations_count - amount of workstations desired (default: 1)  
## How to use?
Use a bash shell with azure CLI, terraform and ansible installed.  
create a .tfvars with the above variables, and then:
```
az login
terraform init
terraform apply -var-file <name>.tfvars
```
