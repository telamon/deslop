#!/bin/sh
# usage: fake-systemone.sh RESPONSE_JSON [PORT]
# One-shot HTTP server: serves the canned SystemOneResponse as a
# /v1/systemone answer for exactly one connection, then exits.
resp_file="$1"; port="${2:-8123}"
body=$(cat "$resp_file")
printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
  "$(printf '%s' "$body" | wc -c)" "$body" > /tmp/fake-systemone.http.$port
exec timeout 15 ncat -l "$port" < /tmp/fake-systemone.http.$port
