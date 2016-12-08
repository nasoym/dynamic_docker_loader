#!/usr/bin/env bash
set -ef -o pipefail

while getopts "p:vi" options; do case $options in
  v) VERBOSE_OPTIONS="-vv" ;;
  p) PORT="$OPTARG" ;;
  i) insecure=1 ;;
esac; done; shift $(( OPTIND - 1 ))

: ${PORT:="8080"}
: ${VERBOSE_OPTIONS:=""}
: ${SERVICE:="$(dirname $0)/service.sh"}
: ${SERVER_PEM_FILE:="certificate/server.pem"}

if [[ "$insecure" -eq 1 ]];then
  socat_listen_command="TCP-LISTEN:${PORT},reuseaddr,fork"
else
  socat_listen_command="OPENSSL-LISTEN:${PORT},reuseaddr,fork,verify=0,cert=${SERVER_PEM_FILE}"
fi

socat \
  $VERBOSE_OPTIONS \
  $socat_listen_command \
  EXEC:"${SERVICE}"

