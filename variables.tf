
variable "public_subnet_cidrs" {
 type        = list(string)
 description = "Public Subnet CIDR values"
 default     = ["10.0.1.0/24", "10.0.2.0/24"]
}
 
// definir sobre que AZ pasamos las subnets.
variable "azs" {
 type        = list(string)
 description = "Availability Zones"
 default     = ["us-west-2a", "us-west-2b"]
}

variable "private_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["10.1.1.0/24", "10.1.2.0/24"]
}


/*
variable "public_in_private_subnet_cidrs" {
 type        = list(string)
 description = "Public-in-Private Subnet CIDR values (testing purposes only)"
 default     = ["10.1.50.0/24"]
}
*/