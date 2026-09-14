# Obsidian Self-hosted LiveSync — CouchDB + Cloudflare Tunnel 部署腳本
# 使用方式：scp 到雲端 VM 後執行
# bash setup-obsync.sh

## 前置條件
# 1. 雲端 Linux VM (Ubuntu 22.04+ 或其他主流發行版)
# 2. Docker 已安裝 (或腳本會嘗試安裝)
# 3. Cloudflare 帳號 + 域名 + Tunnel token

## 設定這些變數再跑腳本：
COUCHDB_USER="admin"

COUCHDB_PASSWORD="CHANGE_ME_TO_A_STRONG_PASSWORD"

COUCHDB_PORT=5984

DOMAIN="obsync.yourdomain.com"      # 你的 Cloudflare 子域名

CLOUDFLARE_TUNNEL_TOKEN=""          # 從 Cloudflare Zero Trust 取得
