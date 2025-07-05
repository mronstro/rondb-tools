from fastapi import FastAPI, Response, BackgroundTasks, HTTPException, Cookie, Query
import re
import signal
import psutil
import uuid
import subprocess
import os
import time
import mysql.connector
import requests
import socket
from threading import Lock
from fastapi.responses import HTMLResponse, Response
from fastapi.middleware.cors import CORSMiddleware


app = FastAPI()
session_lock = Lock()

from pathlib import Path
RUN_DIR = Path("/home/ubuntu/config_files")
MYSQL_HOST="13.12.12.12"
GRAFANA_HOST="13.12.12.11"
MYSQL_PASSWORD="password"
GRAFANA_URL = "http://{GRAFANA_HOST}:3000"
GRAFANA_ADMIN_API_KEY = os.getenv("GRAFANA_ADMIN_API_KEY")  # must be created ahead
MYSQL_CONFIG = {
    "host": MYSQL_HOST,
    "user": "root",
    "password": MYSQL_PASSWORD
}
WORKER_COUNT=4
MAX_ACTIVE_DATABASES = 10

user_sessions = {}  # gui_secret → {"db": ..., "locust_port": ..., "running": True/False}

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://{GRAFANA_HOST}:3000"],  # your frontend origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/favicon.ico")
async def favicon():
    return Response(content="", media_type="image/x-icon")

@app.get("/", response_class=HTMLResponse)
async def index():
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Locust Control UI</title>
        <style>
            body { font-family: Arial, sans-serif; padding: 2em; background: #f9f9f9; }
            button { padding: 0.5em 1em; margin: 0.5em 0; }
            input { padding: 0.5em; margin: 0.5em 0; }
        </style>
    </head>
    <body>
        <h2>Start Test Environment</h2>
        <button onclick="createDatabase()">Create Database</button>
        <div id="db-status"></div>

        <h2>Run Locust</h2>
        <label>Worker Count:</label>
        <input id="workerCount" type="number" value="1" min="1" max="4"/>
        <button onclick="runLocust()">Run Locust</button>
        <div id="locust-status"></div>

        <script>
            async function createDatabase() {
                const res = await fetch('/create-database', {
                    method: 'POST'
                });
                const data = await res.json();
                document.getElementById('db-status').innerText = JSON.stringify(data, null, 2);
            }

            async function runLocust() {
                const count = document.getElementById('workerCount').value;
                const res = await fetch(`/run-locust?worker_count=${count}`, {
                    method: 'POST',
                    credentials: 'include'
                });
                const data = await res.json();
                document.getElementById('locust-status').innerText = JSON.stringify(data, null, 2);
            }
        </script>
    </body>
    </html>
    """

def validate_gui_secret(secret: str) -> bool:
    secret = secret.lower()
    return bool(re.fullmatch(r"[a-f0-9]{8}", secret))

def get_free_port():
    with socket.socket() as s:
        s.bind(('', 0))
        return s.getsockname()[1]

def kill_locust_process(secret: str):
    pid_file = RUN_DIR / f"locust_{secret}.pid"
    if not pid_file.exists():
        return

    try:
        for pid_str in pid_file.read_text().splitlines():
            pid = int(pid_str.strip())
            os.kill(pid, signal.SIGTERM)
        pid_file.unlink()
    except Exception as e:
        print(f"Failed to kill Locust processes for {secret}: {e}")

@app.on_event("startup")
def clean_stale_pid_files():
    print("Checking for stale Locust PID files...")
    for pid_file in RUN_DIR.glob("locust_*.pid"):
        try:
            pid = int(pid_file.read_text().strip())
            if not psutil.pid_exists(pid):
                print(f"Removing stale PID file: {pid_file} (process {pid} not running)")
                pid_file.unlink()
            else:
                print(f"Locust process {pid} still running for {pid_file.stem}")
        except Exception as e:
            print(f"Error reading {pid_file}: {e}")
            pid_file.unlink()  # Clean corrupted files

@app.post("/create-database")
async def create_database(response: Response, background_tasks: BackgroundTasks):
    with session_lock:
        gui_secret = str(uuid.uuid4())[:8]  # short-lived secret
        db_name = f"db_{gui_secret}"
        user_cookie = f"X-AUTH={gui_secret}; Path=/"

        active_dbs = len(user_sessions)
        if active_dbs >= MAX_ACTIVE_DATABASES:
            raise HTTPException(status_code=429, detail="Maximum number of active databases reached")

        locust_port = get_free_port()
        user_sessions[gui_secret] = {"db": db_name, "locust_port": locust_port}

    # 1. Create DB + table
    db_name_sql = db_name.replace("`", "")
    conn = mysql.connector.connect(**MYSQL_CONFIG)
    cursor = conn.cursor()
    cursor.execute(f"CREATE DATABASE `{db_name_sql}`")
    cursor.execute(f"USE benchmark")
    call_sql = (
        f"CALL generate_table_data("
        f"'{db_name_sql}',"         # database name
        f"'bench_tbl',"             # table name
        f"10,"                      # column count
        f"100000,"                  # row count
        f"1000,"                    # batch size
        f"1)"                       # column_info
    )
    cursor.execute(call_sql)
    conn.commit()
    cursor.close()
    conn.close()

    # 2. Create Grafana API key with TTL (10 min)
    grafana_key_name = f"key_{gui_secret}"
    api_key = None
    res = requests.post(f"{GRAFANA_URL}/api/auth/keys",
                        headers={"Authorization": f"Bearer {GRAFANA_ADMIN_API_KEY}"},
                        json={
                            "name": grafana_key_name,
                            "role": "Viewer",
                            "secondsToLive": 600
                        })
    if res.status_code == 200:
        api_key = res.json()["key"]
    else:
        raise Exception("Failed to create Grafana API key")

    # 3. Write NGINX config
    config = generate_nginx_config(gui_secret, 8089, 3000)  # Locust + Grafana ports
    config_path = RUN_DIR / f"nginx_conf_{gui_secret}.conf"
    config_path.write_text(config)

    subprocess.run(["nginx", "-s", "reload"])

    # 4. Schedule background cleanup
    background_tasks.add_task(cleanup, gui_secret, db_name, config_path, grafana_key_name)

    # 5. Send access cookie
    response.set_cookie("X-AUTH", gui_secret, max_age=600, httponly=True, secure=True)
    return {"message": "Database created", "gui_secret": gui_secret, "grafana_api_key": api_key}

@app.post("/run-locust")
async def run_locust(
    X_AUTH: str = Cookie(None),
    worker_count: int = Query(0, ge=1, le=WORKER_COUNT)
):
    if not X_AUTH or not validate_gui_secret(X_AUTH) or X_AUTH not in user_sessions:
        raise HTTPException(status_code=403, detail="Invalid or expired session")

    session = user_sessions[X_AUTH]
    db_name = session["db"]
    locust_port = session["locust_port"]
    pid_file = RUN_DIR / f"locust_{X_AUTH}.pid"

    # Prevent double-start
    if pid_file.exists():
        return {"message": f"Locust already running on /{X_AUTH}/locust/"}

    # Check if already running (optional: track PID)
    try:
        conn = mysql.connector.connect(**MYSQL_CONFIG)
        cursor = conn.cursor()
        cursor.execute(f"USE {db_name}")
    except:
        raise HTTPException(status_code=404, detail="Database not found")
    finally:
        cursor.close()
        conn.close()

    env = os.environ.copy()
    env["LOCUST_DATABASE_NAME"] = db_name

    # Start master
    master_proc = subprocess.Popen([
        "locust",
        "-f", "/home/ubuntu/scripts/locust_batch_read.py",
        "--host", "http://localhost:8089",
        "--web-port", str(locust_port),
        "--master"
    ], env=env)

    # Start workers
    worker_procs = []
    for i in range(worker_count):
        proc = subprocess.Popen([
            "locust",
            "-f", "/home/ubuntu/scripts/locust_batch_read.py",
            "--host", "http://localhost:8089",
            "--worker",
            "--master-host", "127.0.0.1"
        ], env=env)
        worker_procs.append(proc)

    # Save all PIDs to one file (optional: or separate files)
    all_pids = [master_proc.pid] + [p.pid for p in worker_procs]
    pid_file.write_text("\n".join(map(str, all_pids)))

    return {"message": f"Distributed Locust UI started at /{X_AUTH}/locust/ with {WORKER_COUNT} workers"}

def generate_nginx_config(secret: str, locust_port: int, grafana_port: int):
    return f"""
map $http_upgrade $connection_upgrade {{
    default upgrade;
    ''      close;
}}
limit_req_zone $binary_remote_addr zone=perip:10m rate=1r/s;

server {{
    listen 8080;

    location ~ ^/{secret}/locust(/.*)?$ {{
        limit_req zone=perip burst=2 nodelay;

        if ($http_cookie !~* "X-AUTH={secret}") {{
            return 403;
        }}
        limit_except GET POST HEAD {{
            deny all;
        }}
        proxy_pass http://localhost:{locust_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }}

    location ~ ^/{secret}/grafana(/.*)?$ {{
        limit_req zone=perip burst=2 nodelay;

        if ($http_cookie !~* "X-AUTH={secret}") {{
            return 403;
        }}
        limit_except GET POST HEAD {{
            deny all;
        }}
        proxy_pass http://GRAFANA_HOST:{grafana_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }}
    location / {{
        return 404;
    }}
}}
"""

def cleanup(gui_secret: str, db_name: str, nginx_conf: str, grafana_key_name: str):
    time.sleep(600)  # wait 10 min

    kill_locust_process(gui_secret)
    # Drop DB
    db_name_sql = db_name.replace("`", "")
    conn = mysql.connector.connect(**MYSQL_CONFIG)
    cursor = conn.cursor()
    cursor.execute(f"DROP DATABASE IF EXISTS `{db_name_sql}`")
    conn.commit()
    cursor.close()
    conn.close()

    # Delete API key (optional, since TTL is set)
    requests.delete(f"{GRAFANA_URL}/api/auth/keys/uid/{grafana_key_name}",
                    headers={"Authorization": f"Bearer {GRAFANA_ADMIN_API_KEY}"})

    # Remove NGINX config + reload
    os.remove(nginx_conf)
    subprocess.run(["nginx", "-s", "reload"])

    # Safely remove session from user_sessions
    with session_lock:
        user_sessions.pop(gui_secret, None)
