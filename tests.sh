#!/usr/bin/env bash
set -ef -o pipefail
set -x

./tests/parse_path.test
./tests/parse_headers.test
./tests/service_test

