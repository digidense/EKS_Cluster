########################################################
# MINIMAL EC2 INSTANCE
########################################################

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "minimal" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t2.small"

  subnet_id              = local.subnet_ids[0]
  vpc_security_group_ids = local.security_group_ids
}
