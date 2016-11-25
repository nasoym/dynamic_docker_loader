#!/bin/bash
set -ef -o pipefail

. $(dirname $0)/helper_functions.sh

while getopts "r:d:" OPTIONS; do case $OPTIONS in
  r) ROUTES_PATH="$OPTARG" ;;
  d) DEFAULT_ROUTE_HANDLER="$OPTARG" ;;
esac; done; shift $(( OPTIND - 1 ))

read -r REQUEST_METHOD REQUEST_URI REQUEST_HTTP_VERSION
export REQUEST_METHOD 
export REQUEST_URI 
export REQUEST_HTTP_VERSION

export REQUEST_HOST="http://${SOCAT_SOCKADDR}:${SOCAT_SOCKPORT}"

. $(dirname $0)/read_headers_to_vars.sh

if [[ -n "$REQUEST_HEADER_CONTENT_LENGTH" ]] && [[ "$REQUEST_HEADER_CONTENT_LENGTH" -gt "0" ]];then
  read -r -d '' -n "$REQUEST_HEADER_CONTENT_LENGTH" REQUEST_CONTENT
fi
export REQUEST_CONTENT

export REQUEST_PATH="${REQUEST_URI/%\?*/}"
if [[ "${REQUEST_URI}" =~ \? ]]; then
  export REQUEST_QUERIES="${REQUEST_URI#*\?}"
  COMMAND_ARGUMENTS=()
  for I in $(tr '&' '\n' <<<"$REQUEST_QUERIES"); do
    QUERY_KEY=${I//\=*/}
    [[ "${I}" =~ = ]] && QUERY_VALUE="$(urldecode ${I//*\=/})"
    COMMAND_ARGUMENTS+=("--$QUERY_KEY")
    COMMAND_ARGUMENTS+=("$QUERY_VALUE")
  done
fi

REQUEST_PATH_SEGMENT="${REQUEST_PATH}"
until [[ -z "$REQUEST_PATH_SEGMENT" ]] ; do
  if [[ -f "${ROUTES_PATH}${REQUEST_PATH_SEGMENT}" ]];then
    MATCHING_ROUTE_FILE="${ROUTES_PATH}${REQUEST_PATH_SEGMENT}"
    export REQUEST_SUBPATH="${REQUEST_PATH/#$REQUEST_PATH_SEGMENT/}"
    break
  fi
  if [[ "${REQUEST_PATH_SEGMENT}" =~ /$ ]];then
    REQUEST_PATH_SEGMENT="${REQUEST_PATH_SEGMENT/%\//}"
  else
    REQUEST_PATH_SEGMENT="$(dirname $REQUEST_PATH_SEGMENT)"
  fi
done
unset REQUEST_PATH_SEGMENT

if [[ -z "$MATCHING_ROUTE_FILE" ]];then
    if [[ -f "${DEFAULT_ROUTE_HANDLER}" ]]; then
      MATCHING_ROUTE_FILE="${DEFAULT_ROUTE_HANDLER}"
    elif [[ -f "${ROUTES_PATH}/${DEFAULT_ROUTE_HANDLER}" ]]; then
      MATCHING_ROUTE_FILE="${ROUTES_PATH}/${DEFAULT_ROUTE_HANDLER}"
    fi
fi

if [[ -n "$MATCHING_ROUTE_FILE" ]];then
  RESPONSE_CONTENT="$(echo "$REQUEST_CONTENT" | $MATCHING_ROUTE_FILE "${COMMAND_ARGUMENTS[@]}" $(urldecode ${REQUEST_SUBPATH//\// }))"
  if [[ $? -eq 1 ]];then
    echo_response_status_line 500 "Internal Server Error"
    echo_response_default_headers
    echo -e "\r"
    exit 0
  fi
  if [[ "$RESPONSE_CONTENT" =~ ^HTTP\/[0-9]+\.[0-9]+\ [0-9]+ ]];then
    echo "${RESPONSE_CONTENT}"
  else
    echo_response_status_line  
    echo_response_default_headers
    echo -e "Content-Type: text/html\r"
    echo -e "Content-Length: ${#RESPONSE_CONTENT}\r"
    echo -e "\r"
    echo "${RESPONSE_CONTENT}"
  fi
else
  echo_response_status_line 404 "Not Found"
  echo_response_default_headers
  echo -e "\r"
fi

