#!/usr/bin/env bash

set -f -o pipefail

source lib/logger
source lib/authorization
source lib/http_helpers
source lib/parse_path
source lib/parse_request
source lib/internal_commands
source lib/docker
source lib/docker_request
source lib/main

: ${DOCKER_NAMESPACE:="nasoym"}
: ${LOG_FILE:="logs/logs"}

main

