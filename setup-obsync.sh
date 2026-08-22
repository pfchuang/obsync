#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Obsidian Self-hosted LiveSync 部署腳本
# 在 Oracle Free Cloud VM 上部署 CouchDB + Cloudflare Tunnel
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── 顏色 ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 檢查 .env ──
if [[ ! -f .env ]]; then
    error ".env 檔案不存在。請複製 .env.example 為 .env 並填入你的設定值。"
fi
source .env

[[ -z "${COUCHDB_PASSWORD:-}" ]] && error "COUCHDB_PASSWORD 未設定"
[[ "${COUCHDB_PASSWORD}" == "CHANGE_ME_TO_A_STRONG_PASSWORD" ]] && error "請修改 COUCHDB_PASSWORD 為強密碼"
[[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" || "${CLOUDFLARE_TUNNEL_TOKEN}" == "your-tunnel-token-here" ]] && error "CLOUDFLARE_TUNNEL_TOKEN 未設定"

# ── 檢查 Docker ──
if ! command -v docker &>/dev/null; then
    info "Docker 未安裝，嘗試安裝..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq docker.io docker-compose-plugin
        sudo systemctl enable --now docker
        sudo usermod -aG docker "$USER"
        warn "已安裝 Docker。如果接下來失敗，請重新登入（讓 docker group 生效）後重跑腳本。"
    else
        error "無法自動安裝 Docker，請手動安裝後重跑。"
    fi
fi

# ── 檢查 docker compose（plugin 或 standalone）──
if docker compose version &>/dev/null; then
    COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE="docker-compose"
else
    error "找不到 docker compose 或 docker-compose，請安裝。"
fi
info "使用: $COMPOSE"

# ── 啟動服務 ──
info "啟動 CouchDB + Cloudflare Tunnel..."
$COMPOSE up -d

# ── 等 CouchDB 就緒 ──
info "等待 CouchDB 啟動..."
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:5984/_up &>/dev/null; then
        info "CouchDB 已就緒"
        break
    fi
    sleep 2
done
curl -sf http://127.0.0.1:5984/_up &>/dev/null || error "CouchDB 啟動逾時"

# ── Provisioning: 設定 CouchDB for LiveSync ──
info "設定 CouchDB for Self-hosted LiveSync..."

COUCH_URL="http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984"

# 建立 _users 和 _replicator 系統資料庫（如果不存在）
curl -sf -X PUT "${COUCH_URL}/_users" -o /dev/null || true
curl -sf -X PUT "${COUCH_URL}/_replicator" -o /dev/null || true
curl -sf -X PUT "${COUCH_URL}/_global_changes" -o /dev/null || true

# 設定 LiveSync 所需的九項設定
declare -A SETTINGS=(
    # 強制認證
    ["chttpd/require_valid_user"]="true"
    # CORS
    ["httpd/enable_cors"]="true"
    ["cors/origins"]="app://obsidian.md,capacitor://localhost,http://localhost"
    ["cors/credentials"]="true"
    ["cors/headers"]="accept, authorization, content-type, origin, referer"
    ["cors/methods"]="GET, PUT, POST, HEAD, DELETE"
    ["cors/max_age"]="3600"
    # 文件大小上限 50MB
    ["chttpd/max_http_request_size"]="4294967296"
    ["couchdb/max_document_size"]="50000000"
)

for key in "${!SETTINGS[@]}"; do
    section="${key%%/*}"
    param="${key##*/}"
    value="${SETTINGS[$key]}"
    curl -sf -X PUT "${COUCH_URL}/_node/_local/_config/${section}/${param}" \
        -H "Content-Type: application/json" \
        -d "\"${value}\"" -o /dev/null
done
info "CouchDB 設定完成 (${#SETTINGS[@]} 項)"

# ── 建立 Obsidian 同步資料庫 ──
DB_NAME="obsidiannotes"
curl -sf -X PUT "${COUCH_URL}/${DB_NAME}" -o /dev/null || info "資料庫 ${DB_NAME} 已存在"
info "資料庫 '${DB_NAME}' 就緒"

# ── 驗證 ──
echo ""
info "============================================"
info "  部署完成！"
info "============================================"
echo ""
info "CouchDB 本地: http://127.0.0.1:5984"
info "CouchDB 版本: $(curl -sf http://127.0.0.1:5984 | python3 -c 'import sys,json;print(json.load(sys.stdin)["version"])' 2>/dev/null || echo 'unknown')"
info "Cloudflare Tunnel: 透過你設定的域名存取"
echo ""
info "在 Obsidian Self-hosted LiveSync 插件設定："
info "  URI: https://你的域名"
info "  Username: ${COUCHDB_USER}"
info "  Password: (你在 .env 設定的密碼)"
info "  Database: ${DB_NAME}"
echo ""
info "測試連線: curl https://你的域名/_up"
echo ""
warn "記得在 Cloudflare Zero Trust → Tunnels → Public Hostname 設定："
warn "  Subdomain: obsync (或你選的)"
warn "  Service: http://couchdb:5984"
echo ""
