#!/bin/sh

### run cli and check if it's working
### usage (docker-compose.yml):
# healthcheck:
#   test: [ "CMD-SHELL", "healthcheck.sh" ]
litecoin-cli getblockchaininfo || exit 1