#!/usr/bin/env bash
source ./scripts/include.sh

before-start ndb_mgmd
(set -x
 with-restarts ndb_mgmd \
 $bin/ndb_mgmd --initial -f ./config_files/config.ini \
               --nodaemon \
               --configdir="${RUN_DIR}/ndb_mgmd/config" \
               > "${RUN_DIR}/ndb_mgmd/ndb_mgmd.out" 2>&1 &)
after-start ndb_mgmd ""
