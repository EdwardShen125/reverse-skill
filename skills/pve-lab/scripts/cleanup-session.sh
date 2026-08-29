#!/bin/bash
# 内核调试会话清理脚本
# 清理调试会话结束后可能残留的资源
# 用法: bash skills/pve-lab/scripts/cleanup-session.sh [vm_id]
# 默认 VM_ID: 300

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

check_info() {
    echo -e "${NC}  $1"
}

# 参数处理
VM_ID="${1:-300}"
FORCE_MODE=""
if [ "$1" == "--force" ]; then
    FORCE_MODE="--force"
    VM_ID="${2:-300}"
fi

echo "=== 内核调试会话清理 ==="
echo "目标 VM ID: $VM_ID"
echo ""

# 检查是否有正在运行的调试会话
ACTIVE_SESSION=""
if pgrep -f "kd.*com_1" > /dev/null; then
    ACTIVE_SESSION="WinDbg"
fi
if command -v qm &> /dev/null; then
    VM_STATUS=$(qm status "$VM_ID" 2>/dev/null | awk '/status:/ {print $2}' || echo "unknown")
    if [ "$VM_STATUS" == "running" ]; then
        ACTIVE_SESSION="$ACTIVE_SESSION VM"
    fi
fi

# 如果有活动会话且不是强制模式，需要确认
if [ -n "$ACTIVE_SESSION" ] && [ -z "$FORCE_MODE" ]; then
    check_warn "检测到活动会话: $ACTIVE_SESSION"
    echo "清理将终止这些会话"
    echo ""
    read -p "确认继续清理? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "清理已取消"
        exit 0
    fi
    echo ""
elif [ -n "$ACTIVE_SESSION" ] && [ -n "$FORCE_MODE" ]; then
    check_warn "强制模式: 跳过确认，直接清理"
    echo ""
fi

CLEANED=0
SKIPPED=0

# 1. 强制关闭可能残留的 WinDbg 进程
check_info "1. 清理 WinDbg 进程残留"
if pgrep -f "kd.*com_1" > /dev/null; then
    pkill -f "kd.*com_1"
    sleep 1
    if ! pgrep -f "kd.*com_1" > /dev/null; then
        check_pass "WinDbg 进程已清理"
        ((CLEANED++))
    else
        check_fail "WinDbg 进程清理失败"
    fi
else
    check_info "无残留 WinDbg 进程"
    ((SKIPPED++))
fi
echo ""

# 2. 停止 VM
check_info "2. 停止靶机 VM"
if command -v qm &> /dev/null; then
    VM_STATUS=$(qm status "$VM_ID" 2>/dev/null | awk '/status:/ {print $2}' || echo "unknown")
    case "$VM_STATUS" in
        running)
            qm stop "$VM_ID" 2>/dev/null && {
                check_pass "VM $VM_ID 已停止"
                ((CLEANED++))
            } || {
                check_fail "VM $VM_ID 停止失败"
            }
            ;;
        stopped)
            check_info "VM 已处于停止状态"
            ((SKIPPED++))
            ;;
        *)
            check_warn "VM 状态异常: $VM_STATUS"
            ;;
    esac
else
    check_info "qm 命令不可用（非 PVE 宿主）"
    ((SKIPPED++))
fi
echo ""

# 3. 清理临时快照（可选，需要用户确认）
check_info "3. 临时快照清理"
if command -v qm &> /dev/null; then
    TEMP_SNAPSHOTS=$(qm listsnapshot "$VM_ID" 2>/dev/null | grep -E "pre-kd-debug|temp-debug" || "")
    if [ -n "$TEMP_SNAPSHOTS" ]; then
        check_warn "发现临时快照:"
        echo "$TEMP_SNAPSHOTS"
        check_info "   手动清理命令: qm delsnapshot $VM_ID <snapshot-name>"
    else
        check_info "无临时快照需要清理"
        ((SKIPPED++))
    fi
else
    check_info "qm 命令不可用，跳过快照检查"
    ((SKIPPED++))
fi
echo ""

# 5. 记录清理时间
LOG_FILE="/var/log/pve-kernel-debug.log"
if [ -w "$LOG_FILE" ] || [ -w "$(dirname "$LOG_FILE")" ] || [ -w /var/log ]; then
    echo "[$(date)] Session cleanup for VM $VM_ID: $CLEANED cleaned, $SKIPPED skipped" >> "$LOG_FILE" 2>/dev/null || true
    check_info "清理日志已记录"
fi

# 总结
echo "=== 清理完成 ==="
echo -e "${GREEN}清理项: $CLEANED${NC}"
echo -e "${NC}跳过项: $SKIPPED${NC}"
echo ""

if [ $CLEANED -gt 0 ]; then
    echo -e "${GREEN}会话资源已清理 ✅${NC}"
else
    echo -e "${YELLOW}无资源需要清理 ⚠️${NC}"
fi

exit 0
