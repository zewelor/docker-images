#!/bin/bash

set -e

./dehydrated --register --accept-terms

if [ -z "$CF_HOST" ]; then
  ./dehydrated -c -t dns-01 -k $HOOK_PATH
else
  ./dehydrated -c -d $CF_HOST -t dns-01 -k $HOOK_PATH
fi

if [[ -n ${HC_URL} ]]; then
  echo "==> Pinging healthcheck: $HC_URL"
  curl -fsS -k -m 10 --retry 5 -o /dev/null $HC_URL
fi