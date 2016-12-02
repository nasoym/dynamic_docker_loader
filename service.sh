#!/usr/bin/env bash
# set -ef -o pipefail

# . $(dirname $0)/helper_functions.sh

function upper() { echo "$@" | tr '[:lower:]' '[:upper:]'; }

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
done

if [[ -n "$CONTENT_LENGTH" ]] && [[ "$CONTENT_LENGTH" -gt "0" ]];then
  read -r -d '' -n "$CONTENT_LENGTH" REQUEST_CONTENT
fi

pass_on_uri="$( echo "$REQUEST_URI" | sed 's/^\/[^\/]\+\/[^\/]\+\(\/.*$\)/\1/g' )"
docker_image="$( echo "$REQUEST_URI" | sed 's/^\/\([^\/]\+\/[^\/]\+\)\/.*$/\1/g' )"
docker_image="$( echo "$docker_image" | sed -e 's/^_\///g' -e 's/\/_$//g')"

echo "method:$REQUEST_METHOD" >&2
echo "original:$REQUEST_URI" >&2
echo "docker_image:$docker_image" >&2
echo "pass_on_uri:$pass_on_uri" >&2
echo "whoami:$(whoami)" >&2

docker_ports="$(docker ps -f status=running -f ancestor=${docker_image} --format "{{.Ports}}")"
docker_image_id="$(docker ps -f status=running -f ancestor=${docker_image} --format "{{.Image}}")"
docker_image_created="$(docker inspect ${docker_image} | jq -r '.[0].Created')"

if [[ -z "$docker_ports" ]] && [[ -n "$docker_image" ]];then
  echo "run docker_image:$docker_image" >&2
  docker run -d -P $docker_image >&2
  docker_ports="$(docker ps -f status=running -f ancestor=${docker_image} --format "{{.Ports}}")"
fi
if [[ -n "$docker_ports" ]];then
  public_port="$(echo "$docker_ports" | awk -F',' '{print $1}' | sed 's/^.*:\([0-9]*\)->.*$/\1/g')"
  if [[ -n "$public_port" ]];then
    response="$( \
    echo -n "${REQUEST_METHOD} ${pass_on_uri} ${REQUEST_HTTP_VERSION}
${ALL_LINES}${REQUEST_CONTENT}" \
    | socat - TCP:localhost:${public_port} \
    )"
    sed -n '1p' <<<"${response}"
    echo "Docker_Image_Created: ${docker_image_created}"
    sed -n '2,$p' <<<"${response}"
    exit 0
  fi
fi

STATUS_CODE=${1-404}
STATUS_TEXT=${2-"Not Found"}
echo -e "HTTP/1.0 ${STATUS_CODE} ${STATUS_TEXT}\r"
echo -e "Date: $(date -u "+%a, %d %b %Y %T GMT")\r"
echo -e "Expires: $(date -u "+%a, %d %b %Y %T GMT")\r"
echo -e "Server: Socat Bash Server $SERVER_VERSION\r"
echo -e "Connection: close\r"
echo -e "\r"
