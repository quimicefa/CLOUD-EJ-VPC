/*

 https://spacelift.io/blog/terraform-aws-vpc
 https://dev.betterdoc.org/infrastructure/2020/02/04/setting-up-a-nat-gateway-on-aws-using-terraform.html
 https://github.com/saturnhead/blog-examples/blob/main/vpc-peering/main.tf # peering
 https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection # mas peering
 
 limitaciones de peering 
 https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html
 => transit gateway.
 
 
 https://aws.amazon.com/blogs/networking-and-content-delivery/creating-a-single-internet-exit-point-from-multiple-vpcs-using-aws-transit-gateway/
 
 */
 
provider "aws" {
//  region = "us-west-2" # Oregon
  region = "us-east-1"	# Virgnia
} 

// VPC publica
resource "aws_vpc" "vpc_public" {
 cidr_block = "10.0.0.0/20"	// reducir el tamaño de esta VPC para poder definir dos que no solapen?
 
 tags = {
   Name = "public vpc"
 }
}

// subnets publicas en vpc "publica", una por cada AZ
resource "aws_subnet" "public_subnets_in_public_vpc" {
 count      = length(var.public_public_subnet_cidrs)
 vpc_id     = aws_vpc.vpc_public.id
 cidr_block = element(var.public_public_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
 
 tags = {
   Name = "Public Subnet ${count.index + 1} in Public VPC"
 }
}

// subnets privadas en vpc "publica", una por cada AZ
resource "aws_subnet" "private_subnets_in_public_vpc" {
 count      = length(var.public_private_subnet_cidrs)
 vpc_id     = aws_vpc.vpc_public.id
 cidr_block = element(var.public_private_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
 
 tags = {
   Name = "Private Subnet ${count.index + 1} in Public VPC"
 }
}

// IGW en vpc publica
resource "aws_internet_gateway" "gw" {
 vpc_id = aws_vpc.vpc_public.id
 
 tags = {
   Name = "public VPC IG"
 }
}

// crear route table adicional para enrutar trafico de las subredes publicas al IGW
resource "aws_route_table" "public_rt" {
 vpc_id = aws_vpc.vpc_public.id
 
 route {
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
 }
 
 tags = {
   Name = "Route Table"
   Desc = "RT to grant access from public subnets to the internet"
 }
}

// asociar la route table a las subredes publicas:
resource "aws_route_table_association" "public_subnet_asso" {
 count = length(var.public_public_subnet_cidrs)
 subnet_id      = element(aws_subnet.public_subnets_in_public_vpc[*].id, count.index)
 route_table_id = aws_route_table.public_rt.id
}


// hasta aqui tenemos las subnets publicas con acceso a internet por el IGW. //

// NATGW en las subredes publicas de la vpc publica
// extender a todas las subredes publicas?
// hay que pedir explicitamente una elastic ip para los natgws?
resource "aws_eip" "nat_gateway" {
  count = length(var.public_public_subnet_cidrs)
#  vpc = true // error raro con IAM.
  tags = {
    Name = "EIP para los NATGW publicos en vpc publica ${count.index}"
  }
}

// NATGW en subnet(s) publica(s)
resource "aws_nat_gateway" "nat_gateway" {
  count = length(var.public_public_subnet_cidrs)
  allocation_id = element(aws_eip.nat_gateway[*].id, count.index)
  subnet_id = element(aws_subnet.public_subnets_in_public_vpc[*].id, count.index)
  #subnet_id = aws_subnet.nat_gateway.id
  # aws_subnet.nat_gateway.id
  tags = {
    "Name" = "Public NAT GW ${count.index} in public subnet, public vpc"
  }
}

// tablas de enrutamiento para las subnets privadas de la vpc publica.
resource "aws_route_table" "rt_natgw" {
  count = length(var.public_private_subnet_cidrs)
  vpc_id = aws_vpc.vpc_public.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.nat_gateway[*].id, count.index)
  }
  tags = {
    "Name" = "Route table ${count.index} in private subnet, public vpc"
  }
}

// asociar las route table a las subredes privadas de la vpc publica:
resource "aws_route_table_association" "public_private_subnet_asso" {
 count = length(var.public_private_subnet_cidrs)
 subnet_id      = element(aws_subnet.private_subnets_in_public_vpc[*].id, count.index)
 route_table_id = element(aws_route_table.rt_natgw[*].id, count.index)
}

// hasta aqui tenemos las subnets privadas de la vpc publica con las RT asociadas enrutando el tráfico a los respectivos NATGW.


// crear la VPC privada
resource "aws_vpc" "vpc_private" {
// https://docs.aws.amazon.com/vpc/latest/userguide/vpc-cidr-blocks.html	
 cidr_block = "192.168.0.0/20"
 
 tags = {
   Name = "private vpc"
 }
}

// crear las subnets privadas, misma region, una por cada AZ (las mismas que para las publicas) pero con direccionmiento 192.168.x.x
resource "aws_subnet" "private_subnets" {
 count      = length(var.private_private_subnet_cidrs)
 vpc_id     = aws_vpc.vpc_private.id
 cidr_block = element(var.private_private_subnet_cidrs, count.index)
 availability_zone = element(var.azs, count.index)
  
 tags = {
   Name = "Private Subnet ${count.index + 1} in private VPC"
 }
}

// crear la TGW
resource "aws_ec2_transit_gateway" "tgw_01" {
  description = "TGW-01"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
}


// crear los 2 attachments de las subnets privadas de la vpc privada al TGW
// useful? LOL
resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_attachment_private" {
//  count = length(aws_subnet.private_subnets)
  subnet_ids         = [aws_subnet.private_subnets[0].id , aws_subnet.private_subnets[1].id ]
  //["subnet-abc123", "subnet-def456"]  # IDs of the subnets within the VPC to connect
  transit_gateway_id = aws_ec2_transit_gateway.tgw_01.id
  vpc_id             = aws_vpc.vpc_private.id
}


resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_attachment_public" {
  subnet_ids         = [aws_subnet.private_subnets_in_public_vpc[0].id,aws_subnet.private_subnets_in_public_vpc[1].id ]
  transit_gateway_id = aws_ec2_transit_gateway.tgw_01.id
  vpc_id             = aws_vpc.vpc_public.id
}


// tabla de enrutamiento para TGW
resource "aws_ec2_transit_gateway_route_table" "TGW_RTB" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw_01.id
  tags = {
    "name" = "TGW_RTB_VPC_privada_publica"
  }
}

// añadir una ruta 
resource "aws_ec2_transit_gateway_route" "TGW_RTB_VPC_privada_Route_1" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc_attachment_public.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.TGW_RTB.id
}

// asociar la RT al attachment de la TGW.
resource "aws_ec2_transit_gateway_route_table_association" "TGW_RTB_VPC_B_C_Association_1" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc_attachment_private.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.TGW_RTB.id
}



/// ---

resource "aws_ec2_transit_gateway_route_table" "TGW_RTB_2" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw_01.id

  tags = {
    "name" = "TGW_RTB_VPC_publica"
  }
}

resource "aws_ec2_transit_gateway_route" "TGW_RTB_VPC_A_Route_1" {
  destination_cidr_block         = "10.0.0.0/20"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc_attachment_private.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.TGW_RTB_2.id
}

resource "aws_ec2_transit_gateway_route_table_association" "TGW_RTB_VPC_A_Association_1" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc_attachment_public.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.TGW_RTB_2.id
}

/////////////////// elementos solo para diagnosticar //////////////////////////////////






##################################

// SG para asignar a las ec2 que usaremos para comprobar los requerimientos:
resource "aws_security_group" "allow_ssh_icmp_private" {
  name        = "allow_ssh_icmp_private"
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
  name        = "allow_ssh_icmp_public"
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



//////////////////////// a partir de aqui no estoy esguro de si son necesarios estos elementos. ///////////////////////////////









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