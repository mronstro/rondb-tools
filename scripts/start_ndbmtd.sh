#!/usr/bin/env bash
source ./scripts/include.sh

before-start ndbmtd
(set -x
 with-restarts ndbmtd \
 $bin/ndbmtd --initial --ndb-nodeid="${NODEINFO_NODEIDS}" \
             --nodaemon \
             --ndb-connectstring="${NDB_MGMD_PRI}:1186" \
             > "${RUN_DIR}/ndbmtd/ndbmtd.out" 2>&1 &)
after-start ndbmtd ""
