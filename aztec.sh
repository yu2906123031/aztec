#!/usr/bin/env bash
set -euo pipefail

# 颜色样式
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}Aztec alpha-testnet 节点自动部署开始...${RESET}"

# 系统和权限检查
if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️ 此脚本必须以 root 权限运行（请使用 sudo）"
  exit 1
fi

# Docker & Compose 检查或安装
if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
  echo "🐋 未检测到 Docker 或 Compose，正在安装..."
  apt-get update
  apt-get install -y \
    apt-transport-https ca-certificates curl gnupg-agent software-properties-common

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io

  curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
else
  echo "🐋 Docker 与 Compose 已安装。"
fi

# Node.js 检查或安装
if ! command -v node &> /dev/null; then
  echo "🟢 未检测到 Node.js，正在安装..."
  curl -fsSL https://deb.nodesource.com/setup_current.x | bash -
  apt-get install -y nodejs
else
  echo "🟢 Node.js 已安装。"
fi

# 安装 Aztec CLI
echo "⚙️ 安装 Aztec CLI 并初始化测试网..."
curl -sL https://install.aztec.network | bash

export PATH="$HOME/.aztec/bin:$PATH"

if ! command -v aztec-up &> /dev/null; then
  echo "❌ Aztec CLI 安装失败，请检查网络或重试。"
  exit 1
fi

aztec-up alpha-testnet

# 输入配置信息
read -p "▶️ 执行客户端（EL）RPC URL: " ETH_RPC
read -p "▶️ 共识客户端（CL）RPC URL: " CONS_RPC
read -p "▶️ Blob Sink URL（可留空）: " BLOB_URL
read -p "▶️ 验证者私钥: " VALIDATOR_PRIVATE_KEY

# 获取公网 IP
echo "🌐 正在获取公网 IP..."
PUBLIC_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
echo "    → $PUBLIC_IP"

# 写入 .env 配置
cat > .env <<EOF
ETHEREUM_HOSTS="$ETH_RPC"
L1_CONSENSUS_HOST_URLS="$CONS_RPC"
P2P_IP="$PUBLIC_IP"
VALIDATOR_PRIVATE_KEY="$VALIDATOR_PRIVATE_KEY"
DATA_DIRECTORY="/data"
LOG_LEVEL="debug"
EOF

[ -n "$BLOB_URL" ] && echo "BLOB_SINK_URL=\"$BLOB_URL\"" >> .env

# 构建 docker-compose.yml
BLOB_FLAG=""
[ -n "$BLOB_URL" ] && BLOB_FLAG="--sequencer.blobSinkUrl \$BLOB_SINK_URL"

cat > docker-compose.yml <<EOF
version: "3.8"
services:
  node:
    image: aztecprotocol/aztec:0.85.0-alpha-testnet.5
    network_mode: host
    environment:
      - ETHEREUM_HOSTS=\${ETHEREUM_HOSTS}
      - L1_CONSENSUS_HOST_URLS=\${L1_CONSENSUS_HOST_URLS}
      - P2P_IP=\${P2P_IP}
      - VALIDATOR_PRIVATE_KEY=\${VALIDATOR_PRIVATE_KEY}
      - DATA_DIRECTORY=\${DATA_DIRECTORY}
      - LOG_LEVEL=\${LOG_LEVEL}
      - BLOB_SINK_URL=\${BLOB_SINK_URL:-}
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network alpha-testnet --node --archiver --sequencer $BLOB_FLAG'
    volumes:
      - $(pwd)/data:/data
EOF

mkdir -p data

# 启动节点
echo "🚀 正在启动 Aztec 节点..."
docker-compose up -d

# 成功提示
echo -e "\n✅ 节点已启动！"
echo "   查看日志：docker-compose logs -f"
echo "   数据目录：$(pwd)/data"
