#!/usr/bin/env bash
set -ef -o pipefail

while getopts "p:vs" OPTIONS; do case $OPTIONS in
  v) VERBOSE_OPTIONS="-vv" ;;
  p) PORT="$OPTARG" ;;
  i) insecure=1 ;;
esac; done; shift $(( OPTIND - 1 ))

: ${PORT:="8080"}
: ${VERBOSE_OPTIONS:=""}
: ${SERVICE:="$(dirname $0)/service.sh"}

if [[ "$insecure" -eq 1 ]];then
  socat_listen_command="TCP-LISTEN:${PORT},reuseaddr,fork"
else
  socat_listen_command="OPENSSL-LISTEN:${PORT},reuseaddr,fork,verify=0,cert=certificate/server.pem"
fi

socat \
  $VERBOSE_OPTIONS \
  $socat_listen_command \
  EXEC:"${SERVICE}"

