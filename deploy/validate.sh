#!/bin/bash
for i in {1..10}; do
  curl -fs http://localhost:8080/ && exit 0
  sleep 3
done
exit 1