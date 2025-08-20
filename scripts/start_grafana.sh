#!/usr/bin/env bash
source ./scripts/include.sh
before-start grafana
(set -x
 with-restarts grafana \
 grafana-server --homepath /usr/share/grafana \
                --config ./config_files/grafana/grafana.ini \
                > "${RUN_DIR}/grafana/grafana.out" 2>&1 &)
after-start grafana "${RUN_DIR}/grafana/grafana.out"
