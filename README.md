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

## Notes

The proof of concept uses multi-machine fuzzing. The `sync-dir` is on a shared network file system, something that is not recommended by the author due to lock-up issues with NFS. As workaround, we are using `-f` option to have AFL create the input file in `/tmp`. Only internal fuzzer state and crashes are shared over NFS.

## References

* http://lcamtuf.coredump.cx/afl/
* https://hub.docker.com/r/abh1sek/afl-base/
