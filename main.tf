/*

 https://spacelift.io/blog/terraform-aws-vpc
 https://dev.betterdoc.org/infrastructure/2020/02/04/setting-up-a-nat-gateway-on-aws-using-terraform.html
 https://github.com/saturnhead/blog-examples/blob/main/vpc-peering/main.tf # peering
 https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection # mas peering
 
 limitaciones de peering 
 https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html
 => transit gateway.
 
 */
 
provider "aws" {
  region = "us-west-2"	// Oregon
} 

// VPC publica
resource "aws_vpc" "vpc_public" {
 cidr_block = "10.0.0.0/22"	// reducir el tamaño de esta VPC para poder definir dos que no solapen?
 
 tags = {
   Name = "public vpc"
 }
}

// subnets publicas en vpc "publica", una por cada AZ
resource "aws_subnet" "public_subnets" {
 count      = length(var.public_subnet_cidrs)
 vpc_id     = aws_vpc.vpc_public.id
 cidr_block = element(var.public_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
 
 tags = {
   Name = "Public Subnet ${count.index + 1}"
 }
}

// crear el IGW en vpc publica
resource "aws_internet_gateway" "gw" {
 vpc_id = aws_vpc.vpc_public.id
 
 tags = {
   Name = "public VPC IG"
 }
}

// crear route table adicional para enrutar trafico de las subredes publicas al IGW
resource "aws_route_table" "second_rt" {
 vpc_id = aws_vpc.vpc_public.id
 
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
 }
 
 tags = {
   Name = "Route Table"
 }
}

// asociar la route table a las subredes publicas:
resource "aws_route_table_association" "public_subnet_asso" {
 count = length(var.public_subnet_cidrs)
 subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
 route_table_id = aws_route_table.second_rt.id
}


// crear la VPC privada
resource "aws_vpc" "vpc_private" {
 cidr_block = "10.1.0.0/22"	// reducir el tamaño de esta VPC para poder definir dos que no solapen?
 
 tags = {
   Name = "private vpc"
 }
}

// crear las subnets privadas, misma region, una por cada AZ (las mismas que para las publicas)
resource "aws_subnet" "private_subnets" {
 count      = length(var.private_subnet_cidrs)
 vpc_id     = aws_vpc.vpc_private.id
 cidr_block = element(var.private_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
  
 tags = {
   Name = "Private Subnet ${count.index + 1}"
 }
}


##################################

// SG para asignar a las ec2 que usaremos para comprobar los requerimientos:
resource "aws_security_group" "allow_ssh_icmp_private" {
  name        = "allow_ssh_icmp"
  description = "Allow SSH, ICMP traffic"
  vpc_id      = aws_vpc.vpc_private.id

  ingress {
    description      = "SSH from anywhere"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }


  ingress {
    description      = "all ICMP from anywhere"
    from_port        = -1
    to_port          = -1
    protocol         = "icmp"	
    cidr_blocks      = ["0.0.0.0/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "Ej CLOUD VPC (private)"
  }
}



// SG para asignar a las ec2 que usaremos para comprobar los requerimientos:
resource "aws_security_group" "allow_ssh_icmp_public" {
  name        = "allow_ssh_icmp"
  description = "Allow SSH, ICMP traffic"
  vpc_id      = aws_vpc.vpc_public.id

  ingress {
    description      = "SSH from anywhere"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }


  ingress {
    description      = "all ICMP from anywhere"
    from_port        = -1
    to_port          = -1
    protocol         = "icmp"	
    cidr_blocks      = ["0.0.0.0/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "Ej CLOUD VPC (public)"
  }
}

// TODO montar una transit gateway
// TODO: tablas enrutamiento para la TGW




// TODO: crear una subnet publica en la vpc privada a efectos de diagnostico


// establecer peering
/*
resource "aws_vpc_peering_connection" "vpc_peering" {
  #peer_owner_id = var.peer_owner_id -> opcional!
  peer_vpc_id   = aws_vpc.vpc_public.id
  vpc_id        = aws_vpc.vpc_private.id
  auto_accept   = true

  tags = {
    Name = "VPC Peering entre vpc_private y vpc_public"
  }
}
*/


// NATGW en las subredes publica
// extender a todas las subredes publicas?
resource "aws_eip" "nat_gateway" {
  count = length(var.public_subnet_cidrs)
#  vpc = true
  tags = {
    Name = "EIP para los NATGW publicos"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  count = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat_gateway.id
  #subnet_id = element(aws_subnet.public_subnets[*].id, count.index)
  subnet_id = aws_subnet.nat_gateway.id
  # aws_subnet.nat_gateway.id
  tags = {
    "Name" = "Public NAT GW #{count.index}"
  }
}

resource "aws_route_table" "rt_natgw" {
  vpc_id = aws_vpc.vpc_public.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
}

*/

##############################################



# no hace falta asociarla porque no hay subnets privadas en la vpc publica?
/*
resource "aws_route_table_association" "rt_natgw_asso" {
  subnet_id = aws_subnet.instance.id
  route_table_id = aws_route_table.instance.id
}
*/




###################################


/*

// creat NATGW
resource "aws_subnet" "nat_gateway" {
  availability_zone = element(var.azs, count.index)
  cidr_block = element(var.private_subnet_cidrs, count.index)
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name" = "DummyNATGW"
  }
}
*/

/*
// crear la VPC privada
resource "aws_vpc" "public vpc" {
 cidr_block = "10.1.0.0/16"	// reducir el tamaño de esta VPC para poder definir dos que no solapen?
 
 tags = {
   Name = "private vpc"
 }
}




// crear las subnets privadas 
resource "aws_subnet" "private_subnets" {
 count      = length(var.private_subnet_cidrs)
 vpc_id     = aws_vpc.main.id
 cidr_block = element(var.private_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
  
 tags = {
   Name = "Private Subnet ${count.index + 1}"
 }
}


*/