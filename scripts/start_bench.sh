#!/usr/bin/env bash
source ./scripts/include.sh

# Only operate on the first bench node
if [ "$NODEINFO_IDX" != 0 ]; then exit; fi

before-start nginx
(set -x
 # On a successful start, nginx will daemonize itself by default, which doesn't
 # work under `with-restarts`. We use the -g option to turn off daemonization.
 # This also means that we have to background the process with `&`.
 #
 # If there is a problem, nginx will exit with a non-zero exit code. This is a
 # second reason to run it in the background, otherwise the script would exit
 # immediately without giving `after-start` a chance to report the reason for
 # the failure.
 #
 # We provide the error log path using the -e option rather than via
 # configuration, since otherwise we get a spurious warning (see
 # https://stackoverflow.com/questions/34258894)
 with-restarts nginx \
 nginx -c "${CONFIG_FILES}/nginx.conf" \
       -e "${NGINX_ERROR_LOG}" \
       -g 'daemon off;' \
       > "${RUN_DIR}/nginx/nginx.out" 2>&1 &)
after-start nginx "${NGINX_ERROR_LOG}"
