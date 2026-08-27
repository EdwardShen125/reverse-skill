#!/bin/bash
# PVE 实验室紧急重置脚本
# 仅在其他故障排除方法失败时使用
# 用法: bash skills/pve-lab/scripts/emergency-reset.sh [vm_id]
# 默认 VM_ID: 300
#
# 警告: 此脚本会强制终止进程、清理锁文件、重置配置
# 使用前请确保已保存所有重要数据和快照

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

# 参数处理
VM_ID="${1:-300}"
SAFE_MODE=""
if [ "$1" == "--safe" ]; then
    SAFE_MODE="--safe"
    VM_ID="${2:-300}"
    echo -e "${GREEN}=== 安全模式已启用 ===${NC}"
    echo "将在破坏性操作前创建备份快照"
    echo ""
fi

echo -e "${RED}=== PVE 实验室紧急重置 ===${NC}"
echo "目标 VM ID: $VM_ID"
echo ""

# 确认操作
check_warn "警告: 此操作将强制终止所有相关进程和连接"
check_warn "建议在执行前手动保存当前状态"
echo ""
read -p "确认继续? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "操作已取消"
    exit 0
fi
echo ""

STEP=1
BACKUP_CREATED=""

# 0. 安全模式：创建备份快照
if [ -n "$SAFE_MODE" ]; then
    echo "0. 创建备份快照（安全模式）..."
    if command -v qm &> /dev/null; then
        BACKUP_NAME="emergency-backup-$(date +%Y%m%d-%H%M%S)"
        qm snapshot "$VM_ID" "$BACKUP_NAME" 2>/dev/null && {
            check_pass "备份快照已创建: $BACKUP_NAME"
            BACKUP_CREATED="$BACKUP_NAME"
        } || {
            check_warn "备份快照创建失败，继续重置流程"
        }
    else
        check_warn "qm 命令不可用，跳过备份"
    fi
    echo ""
    ((STEP++))
fi

# 1. 强制终止 WinDbg 进程
echo "$STEP. 终止 WinDbg 进程..."
if pgrep -f "kd.*com_1" > /dev/null; then
    pkill -9 -f "kd.*com_1" 2>/dev/null || true
    sleep 2
    if ! pgrep -f "kd.*com_1" > /dev/null; then
        check_pass "WinDbg 进程已终止"
    else
        check_fail "WinDbg 进程终止失败"
    fi
else
    check_pass "无 WinDbg 进程需要终止"
fi
((STEP++))
echo ""

# 2. 优雅停止 VM
echo "$STEP. 优雅停止 VM..."
if command -v qm &> /dev/null; then
    VM_STATUS=$(qm status "$VM_ID" 2>/dev/null | awk '/status:/ {print $2}' || echo "unknown")
    case "$VM_STATUS" in
        running)
            # 先尝试优雅关闭
            qm shutdown "$VM_ID" 2>/dev/null || true
            sleep 10
            # 检查是否停止成功
            VM_STATUS=$(qm status "$VM_ID" 2>/dev/null | awk '/status:/ {print $2}' || echo "unknown")
            if [ "$VM_STATUS" != "running" ]; then
                check_pass "VM 已优雅关闭"
            else
                # 优雅关闭失败，使用强制停止
                check_warn "优雅关闭超时，使用强制停止"
                qm stop "$VM_ID" --skip-lock 2>/dev/null || true
                sleep 5
                # 最后手段：强制终止
                VM_STATUS=$(qm status "$VM_ID" 2>/dev/null | awk '/status:/ {print $2}' || echo "unknown")
                if [ "$VM_STATUS" == "running" ]; then
                    check_warn "强制停止失败，使用 kill 终止"
                    qm kill "$VM_ID" 2>/dev/null || true
                    sleep 5
                fi
                check_pass "VM 已停止"
            fi
            ;;
        stopped)
            check_pass "VM 已处于停止状态"
            ;;
        *)
            check_warn "VM 状态: $VM_STATUS"
            ;;
    esac
else
    check_warn "qm 命令不可用（非 PVE 宿主）"
fi
((STEP++))
echo ""

# 3. 清理锁文件
echo "$STEP. 清理锁文件..."
LOCK_FILES=(
    "/var/lock/qemu-server/lock-$VM_ID.conf"
    "/var/run/qemu-server/lock-$VM_ID.conf"
)
CLEANED=0
for lock_file in "${LOCK_FILES[@]}"; do
    if [ -f "$lock_file" ]; then
        rm -f "$lock_file" 2>/dev/null && ((CLEANED++)) || true
    fi
done
if [ $CLEANED -gt 0 ]; then
    check_pass "已清理 $CLEANED 个锁文件"
else
    check_pass "无锁文件需要清理"
fi
((STEP++))
echo ""

# 4. 重新配置串口
echo "$STEP. 重新配置串口..."
if command -v qm &> /dev/null; then
    # 删除现有串口配置
    qm set "$VM_ID" -delete serial0 2>/dev/null || true
    sleep 1
    # 重新配置为 socket 模式
    qm set "$VM_ID" -serial0 socket 2>/dev/null || true
    SERIAL_CFG=$(qm config "$VM_ID" 2>/dev/null | grep -E "^serial0:" || echo "")
    if [ -n "$SERIAL_CFG" ]; then
        check_pass "串口配置已重置: $SERIAL_CFG"
    else
        check_fail "串口配置重置失败"
    fi
else
    check_warn "qm 命令不可用，跳过串口配置"
fi
((STEP++))
echo ""

# 5. 清理临时快照（跳过备份快照）
echo "$STEP. 清理临时快照..."
if command -v qm &> /dev/null; then
    SNAPSHOTS=$(qm listsnapshot "$VM_ID" 2>/dev/null | grep -E "temp|debug|broken" | awk '{print $2}' || "")
    if [ -n "$SNAPSHOTS" ]; then
        echo "$SNAPSHOTS" | while read snap; do
            # 跳过备份快照（安全模式创建的）
            if [ "$snap" == "$BACKUP_CREATED" ]; then
                check_info "跳过备份快照: $snap"
                continue
            fi
            qm delsnapshot "$VM_ID" "$snap" 2>/dev/null || {
                check_warn "快照删除失败: $snap"
                continue
            }
            check_pass "已删除快照: $snap"
        done
    else
        check_pass "无临时快照需要清理"
    fi
else
    check_warn "qm 命令不可用，跳过快照清理"
fi
((STEP++))
echo ""

# 6. 创建新的基线快照
echo "$STEP. 创建基线快照..."
if command -v qm &> /dev/null; then
    BASELINE_NAME="baseline-$(date +%Y%m%d-%H%M%S)"
    qm snapshot "$VM_ID" "$BASELINE_NAME" 2>/dev/null && {
        check_pass "基线快照已创建: $BASELINE_NAME"
    } || {
        check_fail "基线快照创建失败"
    }
else
    check_warn "qm 命令不可用，跳过快照创建"
fi
((STEP++))
echo ""

# 7. 记录重置操作
LOG_FILE="/var/log/pve-emergency-reset.log"
if [ -w "$LOG_FILE" ] || [ -w "$(dirname "$LOG_FILE")" ] || [ -w /var/log ]; then
    echo "[$(date)] Emergency reset performed for VM $VM_ID" >> "$LOG_FILE" 2>/dev/null || true
    check_pass "重置操作已记录到日志"
fi

# 总结
echo ""
echo -e "${GREEN}=== 紧急重置完成 ===${NC}"
echo ""

# 显示备份快照信息（如果创建了）
if [ -n "$BACKUP_CREATED" ]; then
    check_pass "备份快照: $BACKUP_CREATED"
    echo "如需回滚，执行:"
    echo "  qm rollback $VM_ID $BACKUP_CREATED"
    echo ""
fi

check_warn "重要提示:"
echo "1. 请手动验证系统状态"
echo "2. 使用 check-dependencies.sh 验证环境"
echo "3. 重新开始调试流程"
if [ -n "$BACKUP_CREATED" ]; then
    echo "4. 如重置失败，可回滚到备份快照"
fi
echo ""
echo "验证命令:"
echo "  bash skills/pve-lab/scripts/check-dependencies.sh $VM_ID"
echo ""

exit 0
