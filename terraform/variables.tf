variable "prefix_to_domain_name" {
    type        = map(string)
    default     = {
        "ad-lab" = "test.lab"
    }
    description = "maps azure name prefix to domain name"
    validation {
        condition     = alltrue([for k in keys(var.prefix_to_domain_name) : length(k) < 11])
        error_message = "Hostname in windows must be smaller than 15, hence name prefix must be smaller than 11."
    }
}
variable "location" {
    type        = string
    default     = "West Europe"
    description = "location for all resources"
}

variable "dc_size" {
    type        = string
    default     = "Standard_A4_v2"
    description = "Size for domain controller"
}

variable "ws_size" {
    type        = string
    default     = "Standard_A2_v2"
    description = "Size for workstations"
}

variable "vnet_address_space" {
    type        = string
    default     = "10.0.0.0/8"
    description = "main vnet address space"
}

variable "admin_username" {
    type        = string
    default     = "domainadmin"
    description = "dc admin username"
}

variable "admin_password" {
    type        = string
    description = "dc admin password"
    sensitive   = true
    validation {
        condition     = length(var.admin_password) >= 12 && length(var.admin_password) <= 72
        error_message = "Password length must be between 12 and 72."
    }
}

variable "workstations_count" {
    type    = number
    default = 1
    validation {
        condition     = var.workstations_count < 10
        error_message = "Workstations count must be smaller than 10."
    }
}