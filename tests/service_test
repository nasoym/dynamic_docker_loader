#!/usr/bin/env bash

set -f -o pipefail

source lib/logger
source lib/http_helpers
source lib/parse_path
source lib/internal_commands
# source lib/docker
# source lib/docker_request
source lib/docker_mock
source lib/docker_request_mock
source lib/main

: ${DOCKER_NAMESPACE:="nasoym"}
# : ${LOG_FILE:="logs/logs"}

main

