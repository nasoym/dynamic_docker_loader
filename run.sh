#!/usr/bin/env bash
set -ef -o pipefail

while getopts "p:vs" OPTIONS; do case $OPTIONS in
  v) VERBOSE_OPTIONS="-vv" ;;
  p) PORT="$OPTARG" ;;
  s) ssl="1" ;;
esac; done; shift $(( OPTIND - 1 ))

: ${PORT:="8080"}
: ${VERBOSE_OPTIONS:=""}
: ${SERVICE:="$(dirname $0)/service.sh"}

if [[ "$ssl" -eq 1 ]];then
  socat_listen_command="OPENSSL-LISTEN:${PORT},reuseaddr,fork,verify=0,cert=ssl_test_certificates/server.pem"
else
  socat_listen_command="TCP-LISTEN:${PORT},reuseaddr,fork"
fi

socat \
  $VERBOSE_OPTIONS \
  $socat_listen_command \
  EXEC:"${SERVICE}"

