#!/usr/bin/env bash

URL="http://127.0.0.1:8080/"

if curl --fail --silent --show-error --output /dev/null "$URL"; then
    echo "UP: $URL"
    exit 0
else
    code=$?
    echo "DOWN: $URL (curl exit $code)"
    exit "$code"
fi
