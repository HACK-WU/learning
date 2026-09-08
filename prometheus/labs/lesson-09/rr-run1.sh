#!/usr/bin/env bash
docker exec l9-rrclient python /rr_client.py app_requests_total 3600 9090 2>&1
