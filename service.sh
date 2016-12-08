#!/usr/bin/env bash

set -ef -o pipefail

function upper() { echo "$@" | tr '[:lower:]' '[:upper:]'; }

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
  echo -e "HTTP/1.0 ${STATUS_CODE} ${STATUS_TEXT}\r"
}

function extract_docker_information_from_path() {
  local docker_port docker_version docker_repository docker_request_uri
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
  else
    docker_repository=""
  fi
  : ${docker_port:="-"}
  : ${docker_version:="latest"}
  echo "$docker_port" "$docker_version" "$docker_repository" "$docker_request_uri"
}

: ${DOCKER_NAMESPACE:="nasoym"}

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

read docker_port docker_version docker_repository docker_request_uri < <(extract_docker_information_from_path "$REQUEST_URI")
if [[ -z "$docker_repository" ]]; then
  echo_response_status_line 404 "Not Found"
  exit
fi

authorization_type="${AUTHORIZATION%% *}"
authorization_token="${AUTHORIZATION#* }"

shopt -s nocasematch
if [[ ! "$authorization_type" =~ ^jwt$ ]];then
  echo_response_status_line 401 "Unauthorized"
  exit
fi

if [[ $DRY_RUN -eq 1 || $DEBUG -eq 1 ]];then
  echo "REQUEST_URI:$REQUEST_URI"
  echo "docker_port:$docker_port"
  echo "docker_version:$docker_version"
  echo "docker_repository:$docker_repository"
  echo "docker_request_uri:$docker_request_uri"

  echo "AUTHORIZATION:$AUTHORIZATION"
  echo "authorization_type:$authorization_type"
  echo "authorization_token:$authorization_token"
fi

if [[ $DRY_RUN -ne 1 ]];then
  if ! ./jwt_verify -f public_jwt_keys >/dev/null <<<"$authorization_token"; then
    echo_response_status_line 401 "Unauthorized"
    exit
  fi
fi


if [[ $DRY_RUN -eq 1 ]];then
  docker_image_id="docker_image_id"
  docker_ports="0.0.0.0:32772->80/tcp, 0.0.0.0:32771->443/tcp"
else
  docker_image_id="$(docker ps -f status=running -f ancestor=${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} --format "{{.Image}}" || true)"
  if [[ -z "$docker_image_id" ]];then
    docker run -d -P ${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} >&2 >/dev/null || true
    docker_ports="$(docker ps -f status=running -f ancestor=${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} --format "{{.Ports}}" || true)"
  fi
  docker_ports="$(docker ps -f status=running -f ancestor=${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} --format "{{.Ports}}" || true)"
fi

if [[ $DRY_RUN -eq 1 || $DEBUG -eq 1 ]];then
  echo "docker_image_id:$docker_image_id"
  echo "docker_ports:$docker_ports"
fi

if [[ -n "$docker_ports" ]];then
  if [[ "$docker_port" == "-" ]];then
    public_port="$(awk "BEGIN{RS=\",|\n\";FS=\"->|:\"}{print \$2;exit}" <<<"$docker_ports")"
  else
    public_port="$(awk "BEGIN{RS=\",|\n\";FS=\"->|:\"}{if (\$3==\"${docker_port}/tcp\"){print \$2}}" <<<"$docker_ports")"
  fi

  if [[ -n "$public_port" ]];then
    if [[ $DRY_RUN -eq 1 || $DEBUG -eq 1 ]];then
      echo "public_port:$public_port"

      echo "execute request:"
      echo -n "${REQUEST_METHOD} ${docker_request_uri} ${REQUEST_HTTP_VERSION}
${ALL_LINES}${REQUEST_CONTENT}"

    fi
    if [[ $DRY_RUN -eq 1 ]];then
      response="response
1
2
3
      "
    else
      docker_image_created="$(docker inspect ${DOCKER_NAMESPACE}/${docker_repository}:${docker_version} | jq -r '.[0].Created' || true)"
      response="$( \
      echo -n "${REQUEST_METHOD} ${docker_request_uri} ${REQUEST_HTTP_VERSION}
${ALL_LINES}${REQUEST_CONTENT}" \
      | socat - TCP:localhost:${public_port},shut-none \
      )"
    fi
    sed -n '1p' <<<"${response}"
    echo "Docker_Image_Created: ${docker_image_created}"
    sed -n '2,$p' <<<"${response}"
    # echo "${response}"
    exit 0
  fi
fi

echo_response_status_line 404 "Not Found"

