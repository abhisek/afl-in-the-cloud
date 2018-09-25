#!/bin/bash

sudo mkdir /var/www/html/status > /dev/null 2>&1
while [ true ]; do
   sudo /tmp/afl-whatsup /mnt/efs/fuzzer/output > /tmp/afl.status
   echo "<pre>`cat /tmp/afl.status`</pre>" | sudo tee /var/www/html/status/index.html > /dev/null
   sleep 10
done;