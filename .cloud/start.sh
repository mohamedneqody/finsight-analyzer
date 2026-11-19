#!/usr/bin/env bash
# FinSight cloud bootstrap — runs inside the Codespace (idempotent)
cd /workspaces/finsight-analyzer || exit 1

log() { echo "[$(date +%H:%M:%S)] $*"; }

# 0) load .env into the shell env (bot.py loads it itself; this is for guards)
set -a
[ -f .env ] && . ./.env
set +a

# 1) dependencies (fast no-op when already installed)
if ! python3 -c "import streamlit, plotly, pandas, pdfplumber, openpyxl, pypdfium2, cv2, dotenv, google.genai" >/dev/null 2>&1; then
  log "installing dependencies..."
  pip3 install -q -r requirements.txt || pip3 install -r requirements.txt
fi

# 2) web UI on 8501
if [ -f /tmp/streamlit.pid ] && kill -0 "$(cat /tmp/streamlit.pid)" 2>/dev/null; then
  log "streamlit already running (pid $(cat /tmp/streamlit.pid))"
else
  nohup python3 -m streamlit run app.py --server.port 8501 --server.address 0.0.0.0 --server.headless true >/tmp/streamlit.log 2>&1 &
  echo $! > /tmp/streamlit.pid
  log "streamlit started (pid $!)"
fi

# 3) telegram bot
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
  if [ -f /tmp/bot.pid ] && kill -0 "$(cat /tmp/bot.pid)" 2>/dev/null; then
    log "bot already running (pid $(cat /tmp/bot.pid))"
  else
    nohup python3 bot.py >/tmp/telegram_bot.log 2>&1 &
    echo $! > /tmp/bot.pid
    log "bot started (pid $!)"
  fi
else
  log "TELEGRAM_BOT_TOKEN missing - bot skipped"
fi

# 4) make port 8501 publicly reachable: a brief forward CREATES the tunnel
#    entry (PATCH alone 404s while unregistered), then PATCH flips it public
(gh codespace ports forward 8501:18999 >/dev/null 2>&1 &)
sleep 12
pkill -f "codespace ports forward" 2>/dev/null || true
if gh api -X PATCH "/user/codespaces/$CODESPACE_NAME/codespace_ports/8501" -f visibility=open >/dev/null 2>&1; then
  log "port 8501 is public"
else
  log "WARN: port registered; run 'gh codespace ports visibility 8501:public' outside"
fi

sleep 3
log "streamlit health: $(curl -s http://localhost:8501/_stcore/health || echo 'not up yet')"
log "bot log tail: $(tail -1 /tmp/telegram_bot.log 2>/dev/null || echo 'empty')"
log "READY"
