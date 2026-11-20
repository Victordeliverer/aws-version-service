#!/bin/bash
set -euo pipefail
VERSION=$(cat /opt/hello-svc/version.txt)
mkdir -p /opt/hello-svc/releases

aws codeartifact get-package-version-asset \
  --region eu-west-1 \
  --domain gradle-lab --repository app-releases \
  --format maven --namespace com.victordeliverer --package aws-version-service \
  --package-version "$VERSION" \
  --asset "aws-version-service-${VERSION}.jar" \
  "/opt/hello-svc/releases/aws-version-service-${VERSION}.jar"

ln -sfn "/opt/hello-svc/releases/aws-version-service-${VERSION}.jar" /opt/hello-svc/current.jar
chown -R app:app /opt/hello-svc
