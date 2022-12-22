provider "aws" {
    region = "us-east-2"
    access_key = "AKIAS4MUZIJN5H53OFP6"
    secret_key = "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"
}

# variables
variable "HTTP_PORT" {}
variable "HTTPS_PORT" {}
variable "SSH_PORT" {}
variable "SERVER_INSTANCE_TAG_NAME" {}
variable "SSH_PUBLIC_KEY" {}
variable "PUBLIC_KEY_LOCATION" {}


# 1 create a VPC 
resource "aws_vpc" "preprod_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "preprod-vpc"
  }
}

# 2 Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.preprod_vpc.id

  tags = {
    Name = "aws_preprd_internet_gateway"
  }
}

# 3 Create Custom Route Table
resource "aws_route_table" "preprod_rt" {
  vpc_id = aws_vpc.preprod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id =  aws_internet_gateway.gw.id
  }

  tags = {
    Name = "preprod_rt"
  }
}

# 4 Create Subnet 
resource "aws_subnet" "preprod_subnet-1" {
  vpc_id            = aws_vpc.preprod_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "preprod-subnet"
  }
}

# 5 Create an association between a route 
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.preprod_subnet-1.id
  route_table_id = aws_route_table.preprod_rt.id
}

# 6 Create a Security Group 
resource "aws_security_group" "allow_web" {
  name        = "allow_web_trafic"
  description = "Allow port 80,22 and port 443 inbound traffic"
  vpc_id      = aws_vpc.preprod_vpc.id

  ingress {
    description      = "HTTP"
    from_port        = var.HTTP_PORT
    to_port          = var.HTTP_PORT
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
   ingress {
    description      = "HTTPS"
    from_port        = var.HTTPS_PORT
    to_port          = var.HTTPS_PORT
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
   ingress {
    description      = "SSH"
    from_port        = var.SSH_PORT
    to_port          = var.SSH_PORT
    protocol         = "tcp"
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
    Name = "allow_web"
  }
}

# 7 Create an Interface network with an IP in the Subnet that was created in step 4

resource "aws_network_interface" "preprod_nic" {
  subnet_id       = aws_subnet.preprod_subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

 # attachment {
 #   instance     = aws_instance.web.id
 #   device_index = 1
 # }
}

# 8 Assign an Elastic IP to the the network interface created in step 7
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.preprod_nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [
    aws_internet_gateway.gw,
    aws_instance.web-server-instance
  ]
}
# Create SSH key 
resource "aws_key_pair" "ssh_key" {
  key_name = "ssh_webserver_key"
  public_key = var.SSH_PUBLIC_KEY
  #public_key = file($var.PUBLIC_KEY_LOCATION)
    
}

# 9 create a Ubuntu Server and Install/enable Apache

resource "aws_instance" "web-server-instance" {
  ami               = "ami-0a606d8395a538502"
  instance_type     = "t2.micro"
  availability_zone = "us-east-2a"
  key_name          = aws_key_pair.ssh_key.key_name
  # use script shell instead
  #user_data = file("{$var.user_data_script_location}")
  user_data         = <<EOF
                        #!/bash/bash
                        sudo yum update -y
                        sudo yum install httpd -y
                        sudo systemctl  start  httpd
                        sudo bash -c 'echo Welcome to the Web server created by Terraform Script > /var/www/html/index.html'
                      EOF
  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.preprod_nic.id
  }

  tags = {
    Name = var.SERVER_INSTANCE_TAG_NAME
  }
}

output "Web_server_instance_public_ip" {
    value = aws_eip.one.public_ip
}

output "Web_server_instance_private_ip" {
    value = aws_instance.web-server-instance.private_ip
}

output "Web_server_instance_id" {
    value = aws_instance.web-server-instance.id
}