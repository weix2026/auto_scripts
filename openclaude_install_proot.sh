#!/bin/bash
# =============================================================================
# OpenClaude 一键安装脚本 - proot-distro Debian 版
# 平台：Termux proot-distro Debian (Android 手机 / 平板)
# 架构：Standalone pnpm -> Node.js (LTS) -> @gitlawb/openclaude
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
step()  { echo -e "\n${BLUE}=== $* ===${NC}"; }
die()   { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }

echo -e "\n${GREEN}=== OpenClaude 一键部署 (proot-distro Debian) ===${NC}\n"

# -- 0. proot 环境修复 ----------------------------------------------------------
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export DEBIAN_FRONTEND=noninteractive

# proot 环境 /tmp 可能未就绪
mkdir -p /tmp && chmod 1777 /tmp 2>/dev/null || true

# proot DNS 经常丢失，使用国内公共 DNS 加速
if [[ ! -s /etc/resolv.conf ]]; then
  warn "proot DNS 缺失，写入国内公共 DNS..."
  rm -f /etc/resolv.conf 2>/dev/null || true
  printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > /etc/resolv.conf 2>/dev/null || true
fi

# -- 1. 系统依赖 ----------------------------------------------------------------
step "安装基础依赖"

info "更新软件包列表..."
apt-get update -qq

info "安装必要工具..."
apt-get install -y -qq --no-install-recommends \
  curl ca-certificates git unzip xz-utils >/dev/null

info "清理 apt 缓存 (节省手机存储)..."
apt-get autoremove -y -qq >/dev/null
apt-get clean -qq
rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/*
ok "基础环境就绪"

# -- 2. pnpm v10 ---------------------------------------------------------------
step "安装 pnpm (独立模式)"

export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
mkdir -p "$PNPM_HOME"

if command -v pnpm &>/dev/null && pnpm --version | grep -qE '^10\.'; then
  ok "pnpm 已存在: $(pnpm --version)"
else
  info "获取 pnpm v10 最新版本..."

  case "$(uname -m)" in
    x86_64|amd64)   PNPM_BIN="pnpm-linux-x64" ;;
    aarch64|arm64)   PNPM_BIN="pnpm-linux-arm64" ;;
    *) die "不支持的 CPU 架构: $(uname -m)" ;;
  esac

  PNPM_V10=$(curl -fsSL "https://registry.npmmirror.com/pnpm" \
    | grep -oP '"10\.\d+\.\d+"' | sort -V | tail -1 | tr -d '"')
  [[ -z "$PNPM_V10" ]] && die "无法获取 pnpm v10 最新版本"
  info "目标版本: pnpm v${PNPM_V10}"

  curl -fsSL -o "$PNPM_HOME/pnpm" \
    "https://gh-proxy.org/https://github.com/pnpm/pnpm/releases/download/v${PNPM_V10}/$PNPM_BIN"
  chmod +x "$PNPM_HOME/pnpm"

  pnpm --version | grep -qE '^10\.' || die "pnpm 安装失败"
  ok "pnpm $(pnpm --version) 安装成功"
fi

# -- 3. 镜像加速 ----------------------------------------------------------------
step "配置镜像源"

cat > "$HOME/.npmrc" << 'EOF'
registry=https://registry.npmmirror.com
node-mirror:release=https://npmmirror.com/mirrors/node/
EOF
ok "国内镜像源已配置"

# -- 4. Node.js LTS -------------------------------------------------------------
step "安装 Node.js (LTS)"

info "通过 pnpm 安装 Node.js LTS..."
pnpm env use --global lts >/dev/null 2>&1

command -v node &>/dev/null || die "Node.js 安装失败"
ok "Node.js $(node --version) + npm $(npm --version) 就绪"

# -- 5. openclaude ---------------------------------------------------------------
step "安装 @gitlawb/openclaude"

info "全局安装 openclaude..."
pnpm add -g @gitlawb/openclaude

OC_PKG_DIR=$(pnpm root -g)/@gitlawb/openclaude
if [[ -f "$OC_PKG_DIR/install.cjs" ]]; then
  info "执行 postinstall 安装原生二进制..."
  node "$OC_PKG_DIR/install.cjs"
fi
ok "OpenClaude 安装完成"

# -- 6. 环境变量持久化 -----------------------------------------------------------
step "配置 shell 环境变量"

BASHRC="$HOME/.bashrc"
PROFILE="$HOME/.profile"
TARGET_FILE="$BASHRC"
[[ ! -f "$BASHRC" ]] && TARGET_FILE="$PROFILE"

if grep -q "PNPM_HOME" "$TARGET_FILE" 2>/dev/null; then
  info "环境变量已存在于 $TARGET_FILE"
else
  cat >> "$TARGET_FILE" << 'EOF'

# >>> pnpm + openclaude <<<
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# <<< pnpm + openclaude <<<
EOF
  ok "环境变量已写入 $TARGET_FILE"
fi

# -- 7. 自检 --------------------------------------------------------------------
step "环境健康检查"

check() {
  local name="$1" cmd="$2" arg="${3:---version}"
  if output=$("$cmd" $arg 2>/dev/null); then
    echo -e "  ${GREEN}[OK]${NC}  ${name}: ${CYAN}$(echo "$output" | head -1)${NC}"
  else
    echo -e "  ${RED}[FAIL]${NC} ${name}"
  fi
}

check "pnpm"       "pnpm"
check "Node.js"    "node"       "-v"
check "npm"        "npm"        "-v"
check "openclaude" "openclaude"

# -- 8. 极限清理 (手机存储寸土寸金) -----------------------------------------------
step "极限清理缓存"

pnpm store prune >/dev/null 2>&1 || true
rm -rf ~/.npm ~/.cache/pnpm /tmp/* 2>/dev/null || true
ok "空间回收完成"

# -- 完成 -----------------------------------------------------------------------
echo -e "\n${GREEN}===========================================${NC}"
echo -e "  ${CYAN}source ~/.bashrc${NC}  (激活当前会话)"
echo -e "  ${CYAN}openclaude${NC}        (启动应用)"
echo -e "${GREEN}===========================================${NC}\n"
