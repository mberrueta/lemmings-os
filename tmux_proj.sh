#!/usr/bin/env zsh
set -u

SESSION="${TMUX_SESSION_NAME:-lemmings_os}"
# Resolve the repository root from the script location so tmux panes open here
# even when the script is launched from another directory.
# Example: running
# `/path/to/repo/tmux_proj.sh` while your shell is currently in `~/tmp`.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MIX_PORT="${MIX_PORT:-4000}"
TIDEWAVE_PORT="${TIDEWAVE_PORT:-4001}"
LIVE_DEBUGGER_PORT="${LIVE_DEBUGGER_PORT:-4002}"
TEST_PORT="${TEST_PORT:-$LIVE_DEBUGGER_PORT}"
PORT="${PORT:-$MIX_PORT}"

cd "$SCRIPT_DIR" || {
  echo "ERROR: failed to cd to $SCRIPT_DIR"
  exit 1
}

COLS=$(tput cols 2>/dev/null || echo 160)
LINES=$(tput lines 2>/dev/null || echo 45)

inside_tmux() { [[ -n "${TMUX-}" ]]; }

has_mix_task() {
  MIX_NO_SYNC=1 mix help "$1" >/dev/null 2>&1
}

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux new-session -d -s "$SESSION" -n MAIN -c "$SCRIPT_DIR" -x "$COLS" -y "$LINES"

  tmux new-window -t "$SESSION" -n SERVER -c "$SCRIPT_DIR"
  if has_mix_task tidewave; then
    tmux split-window -v -p 75 -t "$SESSION:SERVER"
    tmux select-window -t "$SESSION:SERVER"
    tmux select-pane -U
    tmux send-keys "TIDEWAVE_PORT=${TIDEWAVE_PORT} mix tidewave" C-m
    tmux select-pane -D
  fi
  tmux send-keys -t "$SESSION:SERVER" "PORT=${PORT} MIX_PORT=${MIX_PORT} mix phx.server" C-m

  tmux new-window -t "$SESSION" -n IEX -c "$SCRIPT_DIR"
  tmux send-keys -t "$SESSION:IEX" "PORT=${PORT} MIX_PORT=${MIX_PORT} iex -S mix" C-m

  tmux new-window -t "$SESSION" -n LLM -c "$SCRIPT_DIR"
  tmux select-window -t "$SESSION:MAIN"
fi

if inside_tmux; then
  tmux switch-client -t "$SESSION" || {
    echo "ERROR: tmux switch-client failed"
    zsh
  }
else
  tmux attach -t "$SESSION" || {
    echo "ERROR: tmux attach failed"
    zsh
  }
fi
