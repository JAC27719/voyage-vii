#!/bin/sh
set -eu

data_file="/data/${TIGERBEETLE_CLUSTER_ID}_0.tigerbeetle"

case "${1:-start}" in
  init)
    if [ ! -f "$data_file" ]; then
      tigerbeetle format \
        --cluster="$TIGERBEETLE_CLUSTER_ID" \
        --replica=0 \
        --replica-count=1 \
        --development \
        "$data_file"
    fi
    ;;
  start)
    if [ ! -f "$data_file" ]; then
      tigerbeetle format \
        --cluster="$TIGERBEETLE_CLUSTER_ID" \
        --replica=0 \
        --replica-count=1 \
        --development \
        "$data_file"
    fi
    exec tigerbeetle start \
      --addresses=0.0.0.0:3000 \
      --development \
      --cache-grid=256MiB \
      "$data_file"
    ;;
  *)
    exec tigerbeetle "$@"
    ;;
esac
