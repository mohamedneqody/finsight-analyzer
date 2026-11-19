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

# 4) port 8501 public: the tunnel entry can ONLY be created from OUTSIDE the
#    container (in-container gh lacks the codespace scope — verified twice).
#    تشغيل_السحابة.bat and the keepalive workflow own this step:
#      gh codespace ports forward 8501:18999 -c <cs>   # ~12s, then kill it
#      gh codespace ports visibility 8501:public -c <cs>
log "NOTE: public URL still 404? run the port trigger from outside (bat/workflow)"

sleep 3
log "streamlit health: $(curl -s http://localhost:8501/_stcore/health || echo 'not up yet')"
log "bot log tail: $(tail -1 /tmp/telegram_bot.log 2>/dev/null || echo 'empty')"
log "READY"
