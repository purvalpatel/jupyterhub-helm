#!/bin/bash
set -e
echo "starting dind" >>/tmp/purval.txt
dockerd &

# Start SSH server
service ssh start
