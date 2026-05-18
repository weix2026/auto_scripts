#!/bin/bash
# =============================================================================
# kimi 一键安装脚本 - proot-distro Debian 版
# 平台：Termux proot-distro Debian (Android 手机 / 平板)
# 架构：uv -> Python 3.13 -> kimi-cli
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
step()  { echo -e "\n${BLUE}=== $* ===${NC}"; }
die()   { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }

echo -e "\n${GREEN}=== kimi 一键部署 (proot-distro Debian) ===${NC}\n"

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

# -- 2. uv ----------------------------------------------------------------------
step "安装 uv (Python 包管理器)"

export UV_HOME="$HOME/.local/bin"
export PATH="$UV_HOME:$PATH"
mkdir -p "$UV_HOME"

if command -v uv &>/dev/null && uv --version | grep -qE '^uv\s+'; then
  ok "uv 已存在: $(uv --version | head -1)"
else
  info "通过官方脚本安装 uv..."
  # INSTALLER_NO_MODIFY_PATH=1 防止自动修改 shell 配置，我们手动管理
  export INSTALLER_NO_MODIFY_PATH=1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://astral.sh/uv/install.sh | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://astral.sh/uv/install.sh | sh
  else
    die "curl 或 wget 至少需要其一"
  fi

  command -v uv &>/dev/null || die "uv 安装失败"
  ok "uv $(uv --version | head -1) 安装成功"
fi

# -- 3. kimi-cli ----------------------------------------------------------------
step "安装 kimi-cli"

info "通过 uv 安装 kimi-cli (Python 3.13)..."
uv tool install --python 3.13 kimi-cli

# uv tool 安装的命令通常链接到 ~/.local/bin，已在 PATH 中
if command -v kimi &>/dev/null; then
  ok "kimi-cli 安装完成: $(kimi --version 2>/dev/null || echo 'kimi')"
elif command -v kimi-cli &>/dev/null; then
  ok "kimi-cli 安装完成: $(kimi-cli --version 2>/dev/null || echo 'kimi-cli')"
else
  die "kimi-cli 安装后命令未找到"
fi

# -- 4. 环境变量持久化 -----------------------------------------------------------
step "配置 shell 环境变量"

BASHRC="$HOME/.bashrc"
PROFILE="$HOME/.profile"
TARGET_FILE="$BASHRC"
[[ ! -f "$BASHRC" ]] && TARGET_FILE="$PROFILE"

if grep -q "UV_HOME" "$TARGET_FILE" 2>/dev/null; then
  info "环境变量已存在于 $TARGET_FILE"
else
  cat >> "$TARGET_FILE" << 'EOF'

# >>> uv + kimi <<<
export UV_HOME="$HOME/.local/bin"
case ":$PATH:" in
  *":$UV_HOME:") ;;
  *) export PATH="$UV_HOME:$PATH" ;;
esac
# <<< uv + kimi <<<
EOF
  ok "环境变量已写入 $TARGET_FILE"
fi

# -- 5. 自检 --------------------------------------------------------------------
step "环境健康检查"

check() {
  local name="$1" cmd="$2" arg="${3:---version}"
  if output=$("$cmd" $arg 2>/dev/null); then
    echo -e "  ${GREEN}[OK]${NC}  ${name}: ${CYAN}$(echo "$output" | head -1)${NC}"
  else
    echo -e "  ${RED}[FAIL]${NC} ${name}"
  fi
}

check "uv"        "uv"       "--version"
check "kimi"      "kimi"     "--version"

# -- 6. 极限清理 (手机存储寸土寸金) -----------------------------------------------
step "极限清理缓存"

rm -rf ~/.cache/uv /tmp/* 2>/dev/null || true
ok "空间回收完成"

# -- 完成 -----------------------------------------------------------------------
echo -e "\n${GREEN}===========================================${NC}"
echo -e "  ${CYAN}source ~/.bashrc${NC}  (激活当前会话)"
echo -e "  ${CYAN}kimi${NC}            (启动应用)"
echo -e "${GREEN}===========================================${NC}\n"
