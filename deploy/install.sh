#!/bin/bash
set -euo pipefail
VERSION=$(cat /opt/hello-svc/version.txt)
mkdir -p /opt/hello-svc/releases

aws codeartifact get-package-version-asset \
  --region eu-west-1 \
  --domain gradle-lab --repository app-releases \
  --format maven --namespace com.example --package hello-svc \
  --package-version "$VERSION" \
  --asset "hello-svc-${VERSION}.jar" \
  "/opt/hello-svc/releases/hello-svc-${VERSION}.jar"

ln -sfn "/opt/hello-svc/releases/hello-svc-${VERSION}.jar" /opt/hello-svc/current.jar
chown -R app:app /opt/hello-svc