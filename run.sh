#!/usr/bin/env bash
set -ef -o pipefail

function kill_command(){
  if [[ -n "$COMMAND_PID" ]]; then
    kill -0 $COMMAND_PID &>/dev/null && { 
      kill $COMMAND_PID;
      unset COMMAND_PID
    }
  fi
}

function quit(){
  kill_command
  exit 0
}
trap quit SIGTERM SIGINT SIGHUP EXIT

while getopts "p:vin" options; do case $options in
  v) VERBOSE_OPTIONS="-vv" ;;
  p) PORT="$OPTARG" ;;
  i) insecure=1 ;;
  n) no_auth=1 ;;
esac; done; shift $(( OPTIND - 1 ))

: ${no_auth:=0}
export no_auth

: ${PORT:="8080"}
: ${INTERNAL_PORT:="8081"}
: ${VERBOSE_OPTIONS:=""}
: ${SERVICE:="$(dirname $0)/service.sh"}
: ${INTERNAL_SERVICE:="$(dirname $0)/internal_service.sh"}
: ${SERVER_PEM_FILE:="certificate/server.pem"}

if [[ "$insecure" -eq 1 ]];then
  socat_listen_command="TCP-LISTEN:${PORT},reuseaddr,fork"
else
  socat_listen_command="OPENSSL-LISTEN:${PORT},reuseaddr,fork,verify=0,cert=${SERVER_PEM_FILE}"
fi

socat \
  TCP-LISTEN:${INTERNAL_PORT},reuseaddr,fork \
  EXEC:"${INTERNAL_SERVICE}" &
COMMAND_PID="$!"

socat \
  $VERBOSE_OPTIONS \
  $socat_listen_command \
  EXEC:"${SERVICE}"

