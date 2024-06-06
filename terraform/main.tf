#Configure aws provider
provider "aws" {
  region = var.region
}

#create vpc
resource "aws_vpc" "gfetu_vpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "gfetu_VPC"
  }
}

#Capture vpc_id in output variable
output "vpc_id" {
  value = aws_vpc.gfetu_vpc.id
}


#Create 2 subnets
resource "aws_subnet" "pub_subnet" {
  vpc_id     = aws_vpc.gfetu_vpc.id
  cidr_block = var.cidr_block1

  tags = {
    Name = var.pub_subnet_name
  }
}

resource "aws_subnet" "priv_subnet" {
  vpc_id     = aws_vpc.gfetu_vpc.id
  cidr_block = var.cidr_block2

  tags = {
    Name = var.priv_subnet_name
  }
}


#Create route table and IGW
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.gfetu_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "gfetu_route_table"
  }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.gfetu_vpc.id

  tags = {
    Name = "gfetu_igw"
  }
}

####################################################################################
############################# Frontend VM ##########################################
####################################################################################

resource "aws_route_table_association" "a1" {
  subnet_id      = aws_subnet.pub_subnet.id
  route_table_id = aws_route_table.route_table.id
}


#### security group to allow ssh on frontend VM
resource "aws_security_group" "gfetu_sg_front" {
  vpc_id = aws_vpc.gfetu_vpc.id

  tags = {
    Name = "gfetu_sg_front"
  }
}


resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.gfetu_sg_front.id
  cidr_ipv4         = "137.194.0.0/16"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}


resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_front" {
  security_group_id = aws_security_group.gfetu_sg_front.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}



## create ssh key pair and associate on frontend VM
resource "tls_private_key" "gfetu_key" {
  algorithm   = "RSA"
  rsa_bits    = 4096
}

resource "local_file" "gfetu_private_key" { # chmod 400 ../.ssh/private_key_gfetu_gin208
  filename = "../../.ssh/private_key_gfetu_gin208"
  content  = tls_private_key.gfetu_key.private_key_pem
}


resource "aws_key_pair" "gfetu_project_ssh_key_pair" {
  key_name   = "gfetu_project_ssh_key"
  public_key = tls_private_key.gfetu_key.public_key_openssh
}


#### Create frontend instance 
data "aws_ami" "ami" {
  most_recent = true
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20240301"]
  }
}

resource "aws_instance" "gfetu_frontend" {
  ami                         = data.aws_ami.ami.id
  instance_type               = "t2.nano"
  subnet_id                   = aws_subnet.pub_subnet.id
  key_name                    = aws_key_pair.gfetu_project_ssh_key_pair.key_name
  associate_public_ip_address = true
  source_dest_check           = false
  security_groups             = [aws_security_group.gfetu_sg_front.id]

  tags = {
    Name = "gfetu_frontend"
  }
}

output "public_ip_frontend" {
  value = aws_instance.gfetu_frontend.public_ip
}


####################################################################################
############################# Backend VM ##########################################
####################################################################################

resource "aws_route_table_association" "a2" {
  subnet_id      = aws_subnet.priv_subnet.id
  route_table_id = aws_route_table.route_table.id
}


#### security group to allow ssh on frontend VM
resource "aws_security_group" "gfetu_sg_back" {
  vpc_id = aws_vpc.gfetu_vpc.id

  tags = {
    Name = "gfetu_sg_back"
  }
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4_back" {
  security_group_id = aws_security_group.gfetu_sg_back.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_from_frontend" {
  security_group_id = aws_security_group.gfetu_sg_back.id
  cidr_ipv4         = aws_subnet.pub_subnet.cidr_block
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

### (ssh public key in the back VM, even though no ssh connection opened)
#### Create backend instance 
resource "aws_instance" "gfetu_backend" {
  ami                         = data.aws_ami.ami.id
  instance_type               = "t2.nano"
  subnet_id                   = aws_subnet.priv_subnet.id
  key_name                    = aws_key_pair.gfetu_project_ssh_key_pair.key_name
  associate_public_ip_address = true
  source_dest_check           = false
  security_groups             = [aws_security_group.gfetu_sg_back.id]

  tags = {
    Name = "gfetu_backend"
  }
}

output "public_ip_backend" {
  value = aws_instance.gfetu_backend.public_ip
}

output "private_ip_backend" {
  value = aws_instance.gfetu_backend.private_ip
}





# Generate inventory file
resource "local_file" "inventory" {
  filename = "../inventory.ini"
  content = <<EOF
[frontend]
frontend ansible_host=${aws_instance.gfetu_frontend.public_ip}

[backend]
backend ansible_host=${aws_instance.gfetu_backend.public_ip}

[all:vars]
ansible_ssh_private_key_file=../../.ssh/private_key_gfetu_gin208
ansible_user=ubuntu
EOF
}


#### jump host ssh
resource "local_file" "ssh_instructions" {
filename = "./ssh_instructions.txt"
content = <<EOF
To connect to the backend instance through the frontend jump host, use the following command:
ssh -i ${local_file.gfetu_private_key.filename} -J ubuntu@${aws_instance.gfetu_frontend.public_ip} ubuntu@${aws_instance.gfetu_backend.private_ip}
EOF
}

