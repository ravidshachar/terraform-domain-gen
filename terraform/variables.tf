variable "name_prefix" {
    type        = string
    default     = "ad-lab"
    description = "all resources name prefix"
}
variable "location" {
    type        = string
    default     = "France Central"
    description = "location for all resources"
}

variable "vnet_address_space" {
    type        = list(string)
    default     = ["10.0.0.0/16"]
    description = "main vnet address space"
}

variable "subnet_main" {
    type        = string
    default     = "10.0.0.0/24"
    description = "main subnet cidr"
}

variable "subnet_address_prefixes" {
    type        = list(string)
    default     = ["10.0.0.0/24"]
    description = "internal subnet address prefixes"
}

variable "admin_username" {
    type        = string
    default     = "osher"
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

variable "domain_name" {
    type    = string
    description = "full domain name"
}

variable "workstations_count" {
    type = number
    default = 1
}