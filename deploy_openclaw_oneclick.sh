#!/usr/bin/env bash
set -Eeuo pipefail

# OpenClaw 一鍵部署腳本（Ubuntu VM）
# 用法：
#   chmod +x deploy_openclaw_oneclick.sh
#   ./deploy_openclaw_oneclick.sh
# 可選參數：
#   --skip-upgrade          跳過 apt upgrade
#   --skip-onboard          只安裝，不啟動 onboarding
#   --telegram-token TOKEN  直接配置 Telegram Bot Token
#   --install-chrome        安裝 Google Chrome（避免 Snap Chromium 問題）

SKIP_UPGRADE=0
SKIP_ONBOARD=0
INSTALL_CHROME=0
TELEGRAM_TOKEN=""

log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERR ]\033[0m $*" >&2; }

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --skip-upgrade          跳過 apt upgrade
  --skip-onboard          只安裝 OpenClaw，不跑 onboarding
  --telegram-token TOKEN  新增 Telegram channel token
  --install-chrome        安裝 Google Chrome .deb
  -h, --help              顯示說明
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "缺少命令：$1"
    exit 1
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-upgrade)
      SKIP_UPGRADE=1
      shift
      ;;
    --skip-onboard)
      SKIP_ONBOARD=1
      shift
      ;;
    --telegram-token)
      [[ $# -lt 2 ]] && { err "--telegram-token 需要一個 TOKEN 參數"; exit 1; }
      TELEGRAM_TOKEN="$2"
      shift 2
      ;;
    --install-chrome)
      INSTALL_CHROME=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "未知參數：$1"
      usage
      exit 1
      ;;
  esac
done

if [[ "${EUID}" -eq 0 ]]; then
  err "請不要用 root 直接執行。改用一般帳號執行此腳本。"
  exit 1
fi

require_cmd sudo
require_cmd curl

log "Step 0/8: 更新 Ubuntu 與安裝基礎套件"
sudo apt update
if [[ "${SKIP_UPGRADE}" -eq 0 ]]; then
  sudo apt upgrade -y
else
  warn "已略過 apt upgrade"
fi
sudo apt install -y curl wget git ca-certificates gnupg lsb-release unzip jq net-tools open-vm-tools-desktop

log "Step 1/8: 基本環境檢查"
uname -a
lsb_release -a || true
ip a || true
if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
  log "網路連線正常"
else
  warn "無法 ping 8.8.8.8，請確認 VM 網路設定"
fi

log "Step 2/8: 安裝 OpenClaw"
curl -fsSL https://openclaw.ai/install.sh | bash

log "Step 3/8: 版本確認"
require_cmd openclaw
require_cmd node
openclaw --version
node --version

if [[ "${SKIP_ONBOARD}" -eq 0 ]]; then
  log "Step 4/8: 啟動 onboarding（請依照畫面完成設定）"
  openclaw onboard --install-daemon
else
  warn "已略過 onboarding"
fi

log "Step 5/8: 部署後健康檢查"
openclaw status || true
openclaw gateway status || true
openclaw doctor || true
openclaw health || true

log "Step 6/8: 顯示 Control UI token（若需要）"
openclaw config get gateway.auth.token || true

if [[ -n "${TELEGRAM_TOKEN}" ]]; then
  log "Step 7/8: 新增 Telegram channel"
  openclaw channels add --channel telegram --token "${TELEGRAM_TOKEN}" || true
  openclaw pairing list telegram || true
else
  warn "未提供 Telegram token，略過 Telegram channel 設定"
fi

if [[ "${INSTALL_CHROME}" -eq 1 ]]; then
  log "Step 8/8: 安裝 Google Chrome .deb"
  TMP_DEB="/tmp/google-chrome-stable_current_amd64.deb"
  wget -O "${TMP_DEB}" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  sudo dpkg -i "${TMP_DEB}" || true
  sudo apt --fix-broken install -y
  rm -f "${TMP_DEB}"
else
  warn "未指定 --install-chrome，略過 Chrome 安裝"
fi

cat <<'DONE'

====================================================
OpenClaw 一鍵部署流程已完成。

建議下一步：
1) 打開 Control UI: http://127.0.0.1:18789/
2) 觀察即時 log:   openclaw logs --follow
3) 檢查 channels:   openclaw channels list

如需重跑 onboarding：
  openclaw onboard --install-daemon
====================================================
DONE
