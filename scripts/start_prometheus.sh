#!/usr/bin/env bash
source ./scripts/include.sh

before-start prometheus
(set -x
 with-restarts prometheus \
 prometheus --config.file="${CONFIG_FILES}/prometheus.yml" \
            --storage.tsdb.path="${RUN_DIR}/prometheus/data" \
            > "${RUN_DIR}/prometheus.log" 2>&1 &)
after-start prometheus "${RUN_DIR}/prometheus.log"
