public_key = "${file("~/.ssh/id_rsa.pub")}"
private_key = "${file("~/.ssh/id_rsa")}"
aws_region = "us-east-1"
master_ami = ""
slave_ami = ""
master_count = 1  # Ignored currently
slave_count = 5
fuzzer_image = "<Fuzzer image>"
