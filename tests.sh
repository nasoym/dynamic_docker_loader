#!/usr/bin/env bash
set -ef -o pipefail

for test in $(find ./tests -type f -name "*.test"); do
  echo "====== $test"
  $test
done

