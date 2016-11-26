#!/usr/bin/env bash
set -ef -o pipefail

while getopts "d:p:r:vs" OPTIONS; do case $OPTIONS in
  v) VERBOSE_OPTIONS="-vv" ;;
  p) PORT="$OPTARG" ;;
  *) exit 1 ;;
esac; done; shift $(( OPTIND - 1 ))

: ${PORT:="8080"}
: ${VERBOSE_OPTIONS:=""}
: ${SERVICE:="$(dirname $0)/service.sh"}

socat \
  $VERBOSE_OPTIONS \
  OPENSSL-LISTEN:${PORT},reuseaddr,fork,verify=0,cert=ssl_test_certificates/server.pem \
  EXEC:"${SERVICE}"

