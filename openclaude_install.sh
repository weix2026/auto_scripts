#!/bin/bash
# =============================================================================
# OpenClaude 极简安装脚本 - proot-distro Debian 终极优化版
# 架构：Standalone pnpm -> Node.js (LTS) -> OpenClaude
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
step()  { echo -e "\n${BLUE}=== $* ===${NC}"; }
die()   { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }

echo -e "\n${GREEN}=== OpenClaude 一键部署脚本 ===${NC}\n"

# -- 1. 基础环境与依赖治理 -----------------------------------------------------
step "配置基础环境"

mkdir -p /tmp && chmod 1777 /tmp
export LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive

# 修复 proot DNS (静默处理只读异常，使用国内公共 DNS 提速)
if [[ ! -s /etc/resolv.conf ]]; then
  rm -f /etc/resolv.conf 2>/dev/null || true
  printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > /etc/resolv.conf 2>/dev/null || true
fi

info "安装核心系统依赖..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends curl ca-certificates git unzip >/dev/null

info "执行底层空间清理..."
apt-get autoremove -y -qq >/dev/null
apt-get clean -qq
rm -rf /var/lib/apt/lists/* /var/cache/apt/*
ok "系统依赖就绪"

# -- 2. 部署独立版 pnpm --------------------------------------------------------
step "安装核心驱动: pnpm"

export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
mkdir -p "$PNPM_HOME"

if command -v pnpm &>/dev/null; then
  ok "pnpm 已存在: $(pnpm --version)"
else
  info "拉取 pnpm 独立运行环境..."
  
  # 智能检测 CPU 架构
  ARCH=$(uname -m)
  if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    PNPM_BIN="pnpm-linux-x64"
  elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    PNPM_BIN="pnpm-linux-arm64"
  else
    die "不支持的设备架构: $ARCH"
  fi

  # 直接拉取编译好的独立二进制文件
  curl -fsSL -o "$PNPM_HOME/pnpm" "https://gh-proxy.org/https://github.com/pnpm/pnpm/releases/latest/download/$PNPM_BIN"
  chmod +x "$PNPM_HOME/pnpm"
  
  # 验证是否成功
  if command -v pnpm &>/dev/null; then
    ok "pnpm $(pnpm --version) 部署完毕"
  else
    die "pnpm 下载或安装失败，请检查网络"
  fi
fi

# -- 3. 注入 Node.js LTS -------------------------------------------------------
step "安装运行时: Node.js"

info "配置国内镜像加速引擎..."
# 核心修复：直接将配置写入 ~/.npmrc，完美避开 pnpm 调用 npm 导致的崩溃
cat > "$HOME/.npmrc" << 'EOF'
registry=https://registry.npmmirror.com
node-mirror:release=https://npmmirror.com/mirrors/node/
EOF

info "托管安装 Node.js (LTS)..."
pnpm env use --global lts >/dev/null 2>&1

# 验证安装结果
if command -v node &>/dev/null; then
  ok "Node.js $(node --version) 挂载成功"
  ok "国内 CDN 镜像配置生效"
else
  die "Node.js 安装失败或路径未生效"
fi

# -- 4. 组装 OpenClaude --------------------------------------------------------
step "安装目标应用: OpenClaude"

info "获取并编译 openclaude..."
pnpm add -g @gitlawb/openclaude >/dev/null 2>&1
ok "OpenClaude 安装完成"

# -- 5. 极限存储压榨 -----------------------------------------------------------
step "回收磁盘空间"

info "销毁临时文件与冗余缓存..."
pnpm store prune >/dev/null 2>&1 || true
rm -rf ~/.npm ~/.cache/pnpm /tmp/* 2>/dev/null || true
ok "空间回收完毕"

# -- 6. 环境变量固化 -----------------------------------------------------------
step "写入环境变量"

BASHRC="$HOME/.bashrc"
if ! grep -q "PNPM_HOME" "$BASHRC" 2>/dev/null; then
  cat >> "$BASHRC" << 'EOF'

# >>> pnpm + openclaude <<<
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# <<< pnpm + openclaude <<<
EOF
  ok "已配置 ~/.bashrc"
else
  info "~/.bashrc 已包含环境配置"
fi

# -- 7. 终检 -------------------------------------------------------------------
step "环境自检"

check() {
  local name="$1" bin="$2"
  if command -v "$bin" &>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC}  ${name}: ${CYAN}$("$bin" --version 2>/dev/null | head -n1)${NC}"
  else
    echo -e "  ${RED}[ERR]${NC} ${name}: 模块丢失"
  fi
}

check "包管理器 (pnpm)" "pnpm"
check "运行时   (node)" "node"
check "应用程序 (openclaude)" "openclaude"

# -- 结束 ----------------------------------------------------------------------
echo -e "\n${GREEN}===========================================${NC}"
echo -e "  ${CYAN}source ~/.bashrc${NC}  (激活环境)"
echo -e "  ${CYAN}openclaude${NC}        (启动应用)"
echo -e "${GREEN}===========================================${NC}\n"
