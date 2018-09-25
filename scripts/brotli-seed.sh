#!/bin/bash

cd /mnt/efs/fuzzer/input
wget https://github.com/google/brotli/raw/master/tests/testdata/monkey.compressed
wget https://github.com/google/brotli/raw/master/tests/testdata/random_org_10k.bin
wget https://github.com/google/brotli/raw/master/tests/testdata/backward65536.compressed