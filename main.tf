variable "aws_region" {
  type    = "string"
  default = "us-east-1"
}

variable "fuzzer_image" {
  type = "string"
}

variable "master_count" {
  type    = "string"
  default = "1"
}

variable "slave_count" {
  type    = "string"
  default = "3"
}

variable "public_key" {
  type    = "string"
  default = "${"~/.ssh/id_rsa.pub"}"
}

variable "private_key" {
  type    = "string"
  default = "${"~/.ssh/ida_rsa"}"
}

provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_key_pair" "keypair" {
  key_name   = "tfkey"
  public_key = "${file("~/.ssh/id_rsa.pub")}"
}

resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

// https://github.com/terraform-providers/terraform-provider-aws/blob/master/examples/two-tier/main.tf
resource "aws_security_group" "tf-security-group" {
  name        = "tf_security_group"
  description = "Terraform group with only SSH and HTTP access"
  vpc_id      = "${aws_vpc.default.id}"

  // Allow public access to SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Allow full access within subnet
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.1.0/24"] // default subnet
  }

  // Allow full outgoing access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "shared" {
  creation_token = "shared_storage"

  tags = {
    Name = "Shared-Storage"
  }
}

resource "aws_efs_mount_target" "shared" {
  file_system_id  = "${aws_efs_file_system.shared.id}"
  subnet_id       = "${aws_subnet.default.id}"
  security_groups = ["${aws_security_group.tf-security-group.id}"]
}

resource "aws_iam_role" "tf_ec2_ecr_role" {
  name               = "Fuzzer-Role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
  EOF
}

resource "aws_iam_policy" "ecs_instance_policy" {
  name = "ECS-Access-Policy2"
  path = "/"
  description = "Allow access to ECR"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ecr:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
  EOF
}

resource "aws_iam_role_policy_attachment" "ecs_policy_attach" {
  role       = "${aws_iam_role.tf_ec2_ecr_role.name}"
  policy_arn = "${aws_iam_policy.ecs_instance_policy.arn}"
}

resource "aws_iam_instance_profile" "tf_ec2_profile" {
  name = "TF-EC2-Profile"
  role = "${aws_iam_role.tf_ec2_ecr_role.name}"
}

resource "aws_instance" "master" {
   ami                  = "ami-2757f631"
   instance_type        = "t2.micro"
   key_name             = "${aws_key_pair.keypair.key_name}"
   iam_instance_profile = "${aws_iam_instance_profile.tf_ec2_profile.name}"

   tags = {
      Name = "Master-1"
   }

   vpc_security_group_ids = ["${aws_security_group.tf-security-group.id}"]
   subnet_id              = "${aws_subnet.default.id}"

  connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = "${file("~/.ssh/id_rsa")}"
      host        = self.public_ip
  }

   provisioner "remote-exec" {
      inline = [
         "sudo apt-get update -y",
         "sudo apt-get install -y nfs-common docker.io python-pip wget nginx",
         "sudo mkdir -p /mnt/efs",
         "sudo mount -t nfs4 -o nfsvers=4.1 ${aws_efs_mount_target.shared.dns_name}:/ /mnt/efs",
         "sudo mkdir -p /mnt/efs/meta",
         "sudo touch /mnt/efs/meta/${aws_instance.master.id}",
         "sudo usermod -a -G docker ubuntu",
         "echo core | sudo -i tee /proc/sys/kernel/core_pattern",
         "sudo pip install awscli"
      ]
   }

   provisioner "file" {
      source      = "scripts/poppler-seed.sh"
      destination = "/tmp/seed.sh"
   }

   // Create input/output directory and seed files
   provisioner "remote-exec" {
      inline = [
         "sudo mkdir -p /mnt/efs/fuzzer/input",
         "sudo mkdir -p /mnt/efs/fuzzer/output",
         "sudo chmod -R 777 /mnt/efs/fuzzer",
         "chmod 755 /tmp/seed.sh && /tmp/seed.sh"
      ]
   }

   // Start fuzzer container
   provisioner "remote-exec" {
    inline = [
      "`aws ecr get-login --region ${var.aws_region}`",
      "docker pull ${var.fuzzer_image}",
      "docker run -d -e AFL_FUZZ_MODE=master -v /mnt/efs/fuzzer/input:/data/input -v /mnt/efs/fuzzer/output:/data/output ${var.fuzzer_image}"
    ]
   }

   // Status files
   provisioner "file" {
      source      = "scripts/status.sh"
      destination = "/tmp/status.sh"
   }
   provisioner "file" {
      source      = "scripts/afl-whatsup"
      destination = "/tmp/afl-whatsup"
   }

   provisioner "remote-exec" {
      inline = [
         "chmod 755 /tmp/afl-whatsup",
         "chmod 755 /tmp/status.sh",
         "nohup /tmp/status.sh &"
      ]
   }
}

resource "aws_instance" "slave" {
   ami                  = "ami-2757f631"
   instance_type        = "t2.micro"
   key_name             = "${aws_key_pair.keypair.key_name}"
   iam_instance_profile = "${aws_iam_instance_profile.tf_ec2_profile.name}"
   count                = "${var.slave_count}"

   depends_on = ["aws_instance.master"]

   tags = {
      Name = "Slave-N"
   }

   vpc_security_group_ids = ["${aws_security_group.tf-security-group.id}"]
   subnet_id              = "${aws_subnet.default.id}"

   connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = "${file("~/.ssh/id_rsa")}"
      host        = self.public_ip
   }

   provisioner "remote-exec" {
      inline = [
         "sudo apt-get update -y",
         "sudo apt-get install -y nfs-common docker.io python-pip",
         "sudo mkdir -p /mnt/efs",
         "sudo mount -t nfs4 -o nfsvers=4.1 ${aws_efs_mount_target.shared.dns_name}:/ /mnt/efs",
         "sudo mkdir -p /mnt/efs/meta",
         "sudo touch /mnt/efs/meta/${aws_instance.master.id}",
         "sudo usermod -a -G docker ubuntu",
         "echo core | sudo -i tee /proc/sys/kernel/core_pattern",
         "sudo pip install awscli"
      ]
   }

   // Start fuzzer container
   provisioner "remote-exec" {
    inline = [
      "`aws ecr get-login --region ${var.aws_region}`",
      "docker pull ${var.fuzzer_image}",
      "docker run -d -e AFL_FUZZ_MODE=slave -v /mnt/efs/fuzzer/input:/data/input -v /mnt/efs/fuzzer/output:/data/output ${var.fuzzer_image}"
    ]
   }
}

output "MasterIP" {
   value = "${aws_instance.master.public_ip}"
}

output "EFS" {
   value = "${aws_efs_mount_target.shared.dns_name}"
}
