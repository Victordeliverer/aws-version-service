#!/bin/bash
systemctl daemon-reload
systemctl enable hello-svc
systemctl start hello-svc