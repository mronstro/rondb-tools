#!/usr/bin/env bash
sudo chmod -R 777 /var/log/nginx
export RUN_DIR=/home/ubuntu/workspace/rondb-run
python3 -m venv ${RUN_DIR}/locust
source ${RUN_DIR}/locust/bin/activate
pip install -q --upgrade pip
pip install -q locust psutil fastapi uvicorn mysql-connector-python requests
uvicorn python_server:app --host 0.0.0.0 --port 8000
