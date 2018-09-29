# AFL in the Cloud
Proof of concept implementation of fuzzing workload using AFL as the fuzzer and Terraform to codify infrastructure

## Usage

* Download and install `Terraform` following the [Installation Guide](https://www.terraform.io/intro/getting-started/install.html)
* Edit `terraform.tfvars` as required
* Deploy infrastructure by running the plan

```bash
terraform init
```

```bash
terraform apply
```

To destroy the infrastructure

```
terraform destroy
```

## What it does?

The Terraform script creates a bunch of resources in AWS. The resources basically are

1. EC2 instances for deploying fuzzer containers
2. EFS storage as shared storage across all instances

### Resources Created

1. VPC
2. Internet Gateway
3. Subnet and Route
4. Security Group
5. EFS Storage
6. EFS Mount Target (NFS)
7. IAM Role for attaching to EC2 instances
8. IAM Policy for allowing access to ECR
9. 1 x EC2 instance for `master`
10. N x EC2 instances for `slaves`

## Notes

The setup uses multi-machine fuzzing to achieve scale. The `sync-dir` is on a shared network file system, something which is not recommended by the AFL author due to lock-up issues with NFS. As workaround, we are using `-f` option to have AFL create the input file in `/tmp`. Only internal fuzzer state and crashes are shared over NFS.

## References

* http://lcamtuf.coredump.cx/afl/
* https://hub.docker.com/r/abh1sek/afl-base/
