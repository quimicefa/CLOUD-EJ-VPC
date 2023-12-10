/* 

tercer digito de la IP:
	impar: subnet publica
	par : subnet privada

*/

// definir sobre que AZ pasamos las subnets.
variable "azs" {
 type        = list(string)
 description = "Availability Zones"
 default     = ["us-east-1a", "us-east-1b"]
}


// direccionamiento de todas las subnets
variable "public_public_subnet_cidrs" {
 type        = list(string)
 description = "Public Subnet CIDR values"
 default     = ["10.0.1.0/24", "10.0.3.0/24"]
}
 
variable "public_private_subnet_cidrs" {
 type        = list(string)
 description = "Public Subnet CIDR values"
 default     = ["10.0.2.0/24", "10.0.4.0/24"]
}

// TODO: solo para diagnosticar
variable "private_public_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["192.168.1.0/24", "192.168.3.0/24"]
}
 
variable "private_private_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["192.168.2.0/24", "192.168.4.0/24"]
}


/*
variable "public_in_private_subnet_cidrs" {
 type        = list(string)
 description = "Public-in-Private Subnet CIDR values (testing purposes only)"
 default     = ["10.1.50.0/24"]
}
*/