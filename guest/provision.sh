#!/bin/bash
# Runs inside the guest as the image's normal user. Safe to run repeatedly.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
UNIT_SRC=${UNIT_SRC:-/tmp/raft-computer.service}
[ -s "$UNIT_SRC" ] || { echo "missing or empty $UNIT_SRC" >&2; exit 1; }

# Only set by `./vm init` on a fresh clone, so existing VMs are never renamed.
if [ -n "${GUEST_HOSTNAME:-}" ] && [ "$(hostname)" != "$GUEST_HOSTNAME" ]; then
  echo "==> hostname: $GUEST_HOSTNAME"
  if grep -q '^127.0.1.1' /etc/hosts; then
    sudo sed -i "s/^127.0.1.1.*/127.0.1.1 $GUEST_HOSTNAME/" /etc/hosts
  else
    echo "127.0.1.1 $GUEST_HOSTNAME" | sudo tee -a /etc/hosts >/dev/null
  fi
  sudo hostnamectl set-hostname "$GUEST_HOSTNAME"
fi

echo "==> systemd user services without a login session"
sudo loginctl enable-linger "$USER"

echo "==> system packages (Rust/TiUP build dependencies)"
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  build-essential pkg-config libssl-dev clang cmake git tmux unzip jq ripgrep \
  python3 curl ca-certificates protobuf-compiler

echo "==> GitHub CLI (official apt repository)"
if ! command -v gh >/dev/null; then
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y gh
fi

echo "==> kernel limits for TiKV / tiup playground"
sudo tee /etc/sysctl.d/99-raft-vm.conf >/dev/null <<'SYSCTL'
vm.max_map_count = 1048576
fs.inotify.max_user_watches = 1048576
fs.file-max = 4194304
SYSCTL
sudo sysctl --system >/dev/null
sudo tee /etc/security/limits.d/99-raft-vm.conf >/dev/null <<'LIMITS'
* soft nofile 1048576
* hard nofile 1048576
LIMITS

echo "==> shell environment (~/.profile)"
mkdir -p "$HOME/.config/raft-vm"
touch "$HOME/.config/raft-vm/env"
chmod 600 "$HOME/.config/raft-vm/env"
sed -i '/# >>> raft-vm >>>/,/# <<< raft-vm <<</d' "$HOME/.profile"
cat >> "$HOME/.profile" <<'PROFILE'
# >>> raft-vm >>>
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
# tart exec sessions start with a 1024 soft limit; raise it to the hard limit.
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.tiup/bin:$PATH"
if [ -f "$HOME/.config/raft-vm/env" ]; then set -a; . "$HOME/.config/raft-vm/env"; set +a; fi
# <<< raft-vm <<<
PROFILE
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.tiup/bin:$PATH"

echo "==> Claude Code"
if ! command -v claude >/dev/null; then curl -fsSL https://claude.ai/install.sh | bash; fi

echo "==> Raft Computer"
if ! command -v raft-computer >/dev/null; then curl -fsSL https://cdn.raft.build/computer/install.sh | sh; fi

echo "==> Rust toolchain"
if ! command -v rustup >/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile default
fi

echo "==> TiUP"
if ! command -v tiup >/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://tiup-mirrors.pingcap.com/install.sh | sh
fi

echo "==> raft-computer systemd user unit"
mkdir -p "$HOME/.config/systemd/user"
install -m 644 "$UNIT_SRC" "$HOME/.config/systemd/user/raft-computer.service"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
systemctl --user daemon-reload

echo "==> provisioned: $(claude --version 2>/dev/null | head -1), raft-computer $(raft-computer --version 2>/dev/null), $(rustc --version 2>/dev/null), tiup $(tiup --version 2>/dev/null | head -1)"
