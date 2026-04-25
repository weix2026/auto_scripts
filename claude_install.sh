#!/bin/bash
# =============================================================================
# claude 极简安装脚本 - Debian 13.4 + pnpm v10 独立版
# 架构：Standalone pnpm -> Node.js (LTS) -> @anthropic-ai/claude-code
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
step()  { echo -e "\n${BLUE}=== $* ===${NC}"; }
die()   { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }

echo -e "\n${GREEN}=== claude 一键部署脚本 (Debian 13.4) ===${NC}\n"

# -- 0. 基础环境变量配置 -------------------------------------------------------
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# -- 1. 核心依赖安装 ------------------------------------------------------------
step "安装基础依赖"

info "更新软件包列表..."
apt-get update -qq

info "安装必要工具..."
DEPS="curl ca-certificates git unzip xz-utils"
apt-get install -y -qq --no-install-recommends $DEPS >/dev/null

info "清理缓存释放空间..."
apt-get autoremove -y -qq >/dev/null
apt-get clean -qq
rm -rf /var/lib/apt/lists/* /tmp/* 2>/dev/null || true
ok "基础环境就绪"

# -- 2. pnpm 独立安装 ----------------------------------------------------------
step "安装 pnpm (独立模式)"

export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"

mkdir -p "$PNPM_HOME"

if command -v pnpm &>/dev/null && pnpm --version | grep -qE '^10\.'; then
  ok "pnpm 已存在: $(pnpm --version)"
else
  info "获取 pnpm v10 最新版本..."

  # 智能检测 CPU 架构
  case "$(uname -m)" in
    x86_64|amd64) PNPM_BIN="pnpm-linux-x64" ;;
    aarch64|arm64) PNPM_BIN="pnpm-linux-arm64" ;;
    *) die "不支持的 CPU 架构: $(uname -m)" ;;
  esac

  # 查询 pnpm v10 最新版本号
  PNPM_V10=$(curl -fsSL "https://registry.npmmirror.com/pnpm" | grep -oP '"10\.\d+\.\d+"' | sort -V | tail -1 | tr -d '"')
  [[ -z "$PNPM_V10" ]] && die "无法获取 pnpm v10 最新版本"
  info "目标版本: pnpm v${PNPM_V10}"

  curl -fsSL -o "$PNPM_HOME/pnpm" \
    "https://gh-proxy.org/https://github.com/pnpm/pnpm/releases/download/v${PNPM_V10}/$PNPM_BIN"
  chmod +x "$PNPM_HOME/pnpm"

  if command -v pnpm &>/dev/null && pnpm --version | grep -qE '^10\.'; then
    ok "pnpm $(pnpm --version) 安装成功"
  else
    die "pnpm 安装失败或版本不匹配"
  fi
fi

# -- 3. 配置镜像加速 -----------------------------------------------------------
step "配置镜像源"

cat > "$HOME/.npmrc" << 'EOF'
registry=https://registry.npmmirror.com
node-mirror:release=https://npmmirror.com/mirrors/node/
EOF
ok "国内镜像源已配置"

# -- 4. 安装 Node.js LTS -------------------------------------------------------
step "安装 Node.js (LTS)"

info "安装最新 LTS 版本..."
pnpm env use --global lts >/dev/null 2>&1

NODE_VER=$(node --version)
NPM_VER=$(npm --version)
ok "Node.js ${NODE_VER} + npm ${NPM_VER} 就绪"

# -- 5. 安装 claude ------------------------------------------------------------
step "安装 @anthropic-ai/claude-code"

info "全局安装 claude..."
pnpm add -g @anthropic-ai/claude-code
ok "claude 安装完成"

# -- 6. 环境变量持久化 ---------------------------------------------------------
step "配置 shell 环境变量"

BASHRC="$HOME/.bashrc"
PROFILE="${HOME}/.profile"

# 优先写入 .bashrc，否则写入 .profile
TARGET_FILE="$BASHRC"
if [[ ! -f "$BASHRC" ]]; then
  TARGET_FILE="$PROFILE"
fi

CAT_DONE=0
if grep -q "PNPM_HOME" "$TARGET_FILE" 2>/dev/null; then
  CAT_DONE=1
  info "环境变量已存在于配置文件"
else
  cat >> "$TARGET_FILE" << 'EOF'

# >>> pnpm + claude <<<
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# <<< pnpm + claude <<<
EOF
  CAT_DONE=1
  ok "环境变量已写入 $TARGET_FILE"
fi

# -- 7. 环境自检 ---------------------------------------------------------------
step "环境健康检查"

check() {
  local name="$1" cmd="$2" arg="${3:---version}"
  if output=$("$cmd" $arg 2>/dev/null); then
    echo -e "  ${GREEN}[OK]${NC}  ${name}: ${CYAN}$(echo "$output" | head -1)${NC}"
  else
    echo -e "  ${RED}[FAIL]${NC} ${name}"
  fi
}

check "pnpm" "pnpm"
check "Node.js" "node" "-v"
check "npm" "npm" "-v"
check "claude" "claude" "--version"

# -- 8. 收尾 -------------------------------------------------------------------
step "清理缓存"

pnpm store prune >/dev/null 2>&1 || true
rm -rf ~/.cache/pnpm /tmp/* 2>/dev/null || true
ok "空间回收完成"

# -- 结束 ----------------------------------------------------------------------
echo -e "\n${GREEN}===========================================${NC}"
echo -e "  ${CYAN}~/.bashrc${NC}       (环境变量已配置)"
echo -e "  ${CYAN}source ~/.bashrc${NC}  (激活当前会话)"
echo -e "  ${CYAN}claude${NC}          (启动应用)"
echo -e "${GREEN}===========================================${NC}\n"
