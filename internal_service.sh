#!/usr/bin/env bash

set -f -o pipefail

source lib/logger
source lib/http_helpers
source lib/parse_request
source lib/docker
source lib/internal_commands

: ${DOCKER_NAMESPACE:="nasoym"}
: ${LOG_FILE:="logs/logs"}

parse_request
log "request: ${SOCAT_PEERADDR}:${SOCAT_PEERPORT} ${request_method} ${request_uri}"

log "internal_path: ${request_path}"
echo_response_status_line 200 "Ok"
echo
handle_internal_command ${request_path#/}

