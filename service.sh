#!/usr/bin/env bash

set -ef -o pipefail

function upper() { echo "$@" | tr '[:lower:]' '[:upper:]'; }

function log() {
  if [[ -n "$LOG_FILE" ]];then
    echo "$(date +%FT%T) [$$] $@" >>${LOG_FILE}
  else
    echo "$(date +%FT%T) [$$] $@" >&2
  fi
}

function echo_response_default_headers() { 
  # DATE=$(date +"%a, %d %b %Y %H:%M:%S %Z")
  echo -e "Date: $(date -u "+%a, %d %b %Y %T GMT")\r"
  echo -e "Expires: $(date -u "+%a, %d %b %Y %T GMT")\r"
  echo -e "Connection: close\r"
}

function echo_response_status_line() { 
  local STATUS_CODE STATUS_TEXT
  STATUS_CODE=${1-200}
  STATUS_TEXT=${2-OK}
  log "response: ${STATUS_CODE} ${STATUS_TEXT}"
  echo -e "HTTP/1.0 ${STATUS_CODE} ${STATUS_TEXT}\r"
}

function extract_docker_information_from_path() {
  local docker_port docker_version docker_repository docker_request_uri internal_path
  docker_repository=""
  if [[ "$1" =~ ^/([0-9]+)/([0-9]+\.[0-9]+\.[0-9]+)/([^/]+)(/.*)$ ]];then
    docker_port="${BASH_REMATCH[1]}"
    docker_version="${BASH_REMATCH[2]}"
    docker_repository="${BASH_REMATCH[3]}"
    docker_request_uri="${BASH_REMATCH[4]}"
  elif [[ "$1" =~ ^/([0-9]+)/([^/]+)(/.*)$ ]];then
    docker_port="${BASH_REMATCH[1]}"
    docker_repository="${BASH_REMATCH[2]}"
    docker_request_uri="${BASH_REMATCH[3]}"
    if [[ "$docker_repository" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]];then
      docker_port="-"
      docker_repository="-"
    fi
  elif [[ "$1" =~ ^/([0-9]+\.[0-9]+\.[0-9]+)/([^/]+)(/.*)$ ]];then
    docker_version="${BASH_REMATCH[1]}"
    docker_repository="${BASH_REMATCH[2]}"
    docker_request_uri="${BASH_REMATCH[3]}"
  elif [[ "$1" =~ ^/([^/]+)(/.*)$ ]];then
    docker_repository="${BASH_REMATCH[1]}"
    docker_request_uri="${BASH_REMATCH[2]}"
  elif [[ "$1" =~ ^/([^/]+)$ ]];then
    # docker_repository=""
    internal_path="${BASH_REMATCH[1]}"
    echo "found internal path:$internal_path" >&2
  else
    docker_repository=""
  fi
  : ${internal_path:="-"}
  : ${docker_port:="-"}
  : ${docker_version:="latest"}
  echo "$internal_path" "$docker_port" "$docker_version" "$docker_repository" "$docker_request_uri"
}

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
  if ! ./jwt_verify -f public_jwt_keys >/dev/null <<<"$authorization_token"; then
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
  if [[ "$internal_path" == "update" ]];then
    echo "update"
    images_to_update="$(max_time_diff=120 ./dockerhub_list)"
    echo "images_to_update:$images_to_update"

    DOCKER_NAMESPACE="nasoym"
    for docker_repository in $images_to_update; do
      echo ">>>$docker_repository"
      docker_container_id="$(docker ps -f ancestor=${DOCKER_NAMESPACE}/${docker_repository} --format "{{.ID}}" || true)"
      echo "active docker_container_id:${docker_container_id}"
      for container_id in $docker_container_id; do
        echo "remove container: ${container_id}"
        docker rm -f ${container_id}
      done
      docker pull ${DOCKER_NAMESPACE}/$docker_repository
    done
    # echo "$images_to_update" | parallel 'docker pull nasoym/{}'
  # docker_image_id="$(docker ps -f status=running -f ancestor=${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} --format "{{.Image}}" || true)"

  elif [[ "$internal_path" == "remove" ]];then
    :
    echo "remove all containers"
    docker_container_id="$(docker ps -a --format "{{.ID}}" || true)"
    echo "docker_container_id:${docker_container_id}"
    for container_id in $docker_container_id; do
      echo "remove container: ${container_id}"
      docker rm -f ${container_id}
    done
  elif [[ "$internal_path" == "stop" ]];then
    :
    echo "stop all containers"
    docker_container_id="$(docker ps -f status=running --format "{{.ID}}" || true)"
    echo "docker_container_id:${docker_container_id}"
    for container_id in $docker_container_id; do
      echo "stop container: ${container_id}"
      docker stop ${container_id}
    done
  elif [[ "$internal_path" == "logs" ]];then
    :
    echo "logs"
    if [[ -r ${LOG_FILE} ]]; then
      cat ${LOG_FILE}
    fi
  fi
  exit 0
fi

# docker_ports="0.0.0.0:32772->80/tcp, 0.0.0.0:32771->443/tcp"
docker_image_id="$(docker ps -f status=running -f ancestor=${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} --format "{{.Image}}" || true)"
if [[ -z "$docker_image_id" ]];then
  log "launch docker container: ${docker_repository}"
  docker run -d -P ${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} >&2 >/dev/null || true
else
  log "found running docker image: $docker_image_id"
fi
docker_ports="$(docker ps -f status=running -f ancestor=${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} --format "{{.Ports}}" || true)"

if [[ -n "$docker_ports" ]];then
  log "found public docker ports:${docker_ports}"
  if [[ "$docker_port" == "-" ]];then
    public_port="$(awk "BEGIN{RS=\",|\n\";FS=\"->|:\"}{print \$2;exit}" <<<"$docker_ports")"
  else
    public_port="$(awk "BEGIN{RS=\",|\n\";FS=\"->|:\"}{if (\$3==\"${docker_port}/tcp\"){print \$2}}" <<<"$docker_ports")"
  fi
  log "use public port:${public_port}"

  if [[ -n "$public_port" ]];then
    docker_image_created="$(docker inspect ${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} | jq -r '.[0].Created' || true)"
    log "execute request: ${REQUEST_METHOD} localhost:${public_port}${docker_request_uri}"
    response="$( \
    echo "${REQUEST_METHOD} ${docker_request_uri} ${REQUEST_HTTP_VERSION}
${ALL_LINES}${REQUEST_CONTENT}" \
    | socat - TCP:localhost:${public_port},shut-none \
    )"
    sed -n '1p' <<<"${response}"
    echo "Docker_Image_Created: ${docker_image_created}"
    echo "Docker_Image_Name: ${docker_image_id}"
    sed -n '2,$p' <<<"${response}"
    exit 0
  else
    log "no public port found"
  fi
else
  log "no docker ports found"
fi

log "default reaction 404"
echo_response_status_line 404 "Not Found"

