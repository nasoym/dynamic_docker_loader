#!/usr/bin/env bash

set -f -o pipefail

source lib/logger
source lib/http_helpers
source lib/parse_path
source lib/internal_commands
source lib/docker
source lib/docker_request

function upper() { echo "$@" | tr '[:lower:]' '[:upper:]'; }

: ${DOCKER_NAMESPACE:="nasoym"}
: ${LOG_FILE:="logs/logs"}

read -r REQUEST_METHOD REQUEST_URI REQUEST_HTTP_VERSION

ALL_LINES=""
while read -r HEADER_LINE; do 
  HEADER_LINE="$(echo "$HEADER_LINE" | tr -d '\r')"
  ALL_LINES+="$HEADER_LINE
"
  [[ "$HEADER_LINE" =~ ^$ ]] && { break; } 
  HEADER_KEY="${HEADER_LINE/%: */}"
  HEADER_KEY="$(upper ${HEADER_KEY//-/_} )"
  HEADER_VALUE="${HEADER_LINE/#*: /}"
  if [[ "$HEADER_KEY" = "CONTENT_LENGTH" ]];then
    CONTENT_LENGTH="$HEADER_VALUE"
  fi
  if [[ "$HEADER_KEY" = "AUTHORIZATION" ]];then
    AUTHORIZATION="$HEADER_VALUE"
  fi
 # Thus, a simple "Authorization: JWT <your_token>" would be more appropriate.
done

if [[ -n "$CONTENT_LENGTH" ]] && [[ "$CONTENT_LENGTH" -gt "0" ]];then
  read -r -d '' -n "$CONTENT_LENGTH" REQUEST_CONTENT
fi

log "${SOCAT_PEERADDR}:${SOCAT_PEERPORT} ${REQUEST_METHOD} ${REQUEST_URI}"

authorization_type="${AUTHORIZATION%% *}"
authorization_token="${AUTHORIZATION#* }"

if [[ "$no_auth" -ne 1 ]];then
  shopt -s nocasematch
  if [[ ! "$authorization_type" =~ ^jwt$ ]];then
    log "no jwt authorization found"
    echo_response_status_line 401 "Unauthorized"
    exit
  fi
  if ! ./lib/jwt_verify -f public_jwt_keys >/dev/null <<<"$authorization_token"; then
    log "jwt signature failed"
    echo_response_status_line 401 "Unauthorized"
    exit
  fi
fi

read internal_path docker_port docker_version docker_repository docker_request_uri < <(extract_docker_information_from_path "$REQUEST_URI")
if [[ -z "$docker_repository" && "$internal_path" == "-" ]]; then
  log "no docker_repository or internal_path"
  echo_response_status_line 404 "Not Found"
  exit
fi

if [[ "$internal_path" != "-" ]];then
  echo_response_status_line 200 "Ok"
  echo
  log "handle internal_path:${internal_path}"
  handle_internal_command $internal_path
  exit 0
fi

echo "${REQUEST_METHOD} ${docker_request_uri} ${REQUEST_HTTP_VERSION}
${ALL_LINES}${REQUEST_CONTENT}" | docker_handle_request "$docker_repository" "$docker_version" "$docker_port"

log "default reaction 404"
echo_response_status_line 404 "Not Found"

