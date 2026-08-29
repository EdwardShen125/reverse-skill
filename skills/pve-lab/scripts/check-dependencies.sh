#!/bin/bash
# PVE + WinDbg 内核调试依赖检查脚本
# 在开始调试前运行此脚本验证所有依赖
# 用法: bash skills/pve-lab/scripts/check-dependencies.sh [vm_id]
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
LAB_HOST="${2:-192.168.100.175}"

echo "=== PVE + WinDbg 内核调试依赖检查 ==="
echo "目标 VM ID: $VM_ID"
echo "Lab Host: $LAB_HOST"
echo ""

# 全局状态
PASS=0
FAIL=0
WARN=0

# 1. 检查 PVE MCP 服务
check_info "1. PVE MCP 服务 (8767)"
if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$LAB_HOST:8767/mcp/" 2>/dev/null | grep -q "406\|200"; then
    check_pass "PVE MCP 在线 (8767)"
else
    check_fail "PVE MCP 离线或不可达 (8767)"
    ((FAIL++))
fi
echo ""

# 2. 检查 WinDbg MCP 服务
check_info "2. WinDbg MCP 服务 (8765)"
if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$LAB_HOST:8765/mcp/" 2>/dev/null | grep -q "406\|200"; then
    check_pass "WinDbg MCP 在线 (8765)"
else
    check_fail "WinDbg MCP 离线或不可达 (8765)"
    ((FAIL++))
fi
echo ""

# 3. 检查 VM 存在性
check_info "3. VM ID $VM_ID 存在性"
if command -v qm &> /dev/null; then
    if qm status "$VM_ID" &> /dev/null; then
        check_pass "VM $VM_ID 存在"
    else
        check_fail "VM $VM_ID 不存在或无法访问"
        ((FAIL++))
    fi
else
    check_warn "qm 命令不可用（非 PVE 宿主）"
    ((WARN++))
fi
echo ""

# 4. 检查 VM 电源状态
check_info "4. VM 电源状态"
if command -v qm &> /dev/null; then
    VM_STATUS=$(qm status "$VM_ID" 2>/dev/null | awk '/status:/ {print $2}' || echo "unknown")
    case "$VM_STATUS" in
        running)
            check_pass "VM 运行中"
            check_warn "注意: VM 已在运行，确保没有其他调试会话"
            ;;
        stopped)
            check_pass "VM 已停止（可以启动）"
            ;;
        *)
            check_warn "VM 状态未知: $VM_STATUS"
            ((WARN++))
            ;;
    esac
else
    check_warn "qm 命令不可用，无法检查电源状态"
    ((WARN++))
fi
echo ""

# 5. 检查串口配置
check_info "5. VM 串口配置 (serial0)"
if command -v qm &> /dev/null; then
    SERIAL_CFG=$(qm config "$VM_ID" 2>/dev/null | grep -E "^serial0:" || echo "")
    if [ -n "$SERIAL_CFG" ]; then
        if echo "$SERIAL_CFG" | grep -q "socket"; then
            check_pass "串口配置为 socket 模式: $SERIAL_CFG"
        else
            check_fail "串口未配置为 socket，当前: $SERIAL_CFG"
            ((FAIL++))
        fi
    else
        check_fail "未找到串口配置 (serial0)"
        ((FAIL++))
    fi
else
    check_warn "qm 命令不可用，无法验证串口配置"
    ((WARN++))
fi
echo ""

# 6. 检查 QEMU Agent（guest 内操作需要）
check_info "6. QEMU Agent (guest 内操作需要)"
if command -v qm &> /dev/null; then
    QEMU_AGENT=$(qm config "$VM_ID" 2>/dev/null | grep -E "^agent:" || echo "")
    if [ -n "$QEMU_AGENT" ]; then
        check_pass "QEMU Agent 已启用: $QEMU_AGENT"
    else
        check_warn "QEMU Agent 未启用（guest 内操作将不可用）"
        ((WARN++))
    fi
else
    check_warn "qm 命令不可用，无法验证 QEMU Agent"
fi
echo ""

# 8. 检查快照命名冲突
check_info "8. 快照命名冲突检查"
if command -v qm &> /dev/null; then
    SNAPSHOTS=$(qm listsnapshot "$VM_ID" 2>/dev/null | grep -E "^$VM_ID-" || "")
    if [ -n "$SNAPSHOTS" ]; then
        check_warn "发现现有快照（可能冲突）: $SNAPSHOTS"
        ((WARN++))
    else
        check_pass "无冲突快照"
    fi
else
    check_info "qm 命令不可用，跳过快照检查"
fi
echo ""

# 9. 检查磁盘空间（快照操作需要）
check_info "9. 磁盘空间检查"
if command -v df &> /dev/null; then
    # 检查根分区可用空间
    ROOT_FREE=$(df -h /var/lib/vz 2>/dev/null | awk 'NR==2 {print $4}' || echo "unknown")
    if [ "$ROOT_FREE" != "unknown" ]; then
        echo -e "${NC}     /var/lib/vz 可用空间: $ROOT_FREE"
        # 解析可用空间（简化处理，检查 GB 数值）
        if [[ "$ROOT_FREE" =~ ([0-9.]+)G ]]; then
            GB_VALUE="${BASH_REMATCH[1]}"
            if (( $(echo "$GB_VALUE < 20" | bc -l) )); then
                check_warn "警告: 可用空间少于 20GB，快照操作可能失败"
                ((WARN++))
            else
                check_pass "磁盘空间充足"
            fi
        else
            check_info "   无法解析可用空间数值"
        fi
    else
        check_warn "无法检查 /var/lib/vz 磁盘空间"
        ((WARN++))
    fi
else
    check_info "df 命令不可用，跳过磁盘检查"
fi
echo ""

# 10. 检查网络隔离（可选，恶意样本分析时重要）
check_info "10. 网络隔离状态（可选）"
if command -v qm &> /dev/null; then
    # 检查第一个网卡的网络类型
    FIRST_NIC=$(qm config "$VM_ID" 2>/dev/null | grep -E "^net0:" | head -1 || "")
    if [ -n "$FIRST_NIC" ]; then
        echo -e "${NC}     网卡配置: $FIRST_NIC"
        if echo "$FIRST_NIC" | grep -q "bridge"; then
            BRIDGE=$(echo "$FIRST_NIC" | grep -oP 'bridge=\K[^,]+' || echo "unknown")
            check_info "     桥接网络: $BRIDGE"
            if [ "$BRIDGE" != "vmbr0" ] && [ "$BRIDGE" != "unknown" ]; then
                check_warn "警告: 非隔离桥接（vmbr0 推荐），当前: $BRIDGE"
                ((WARN++))
            fi
        fi
    fi
else
    check_info "qm 命令不可用，跳过网络检查"
fi
echo ""

# 总结
echo "=== 检查完成 ==="
echo "通过: $PASS"
echo "警告: $WARN"
echo "失败: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}所有关键检查通过 ✅${NC}"
    echo "可以开始内核调试流程。"
    exit 0
elif [ $FAIL -gt 0 ]; then
    echo -e "${RED}关键检查失败 ❌${NC}"
    echo "请修复失败项后再开始调试。"
    exit 1
else
    echo -e "${YELLOW}仅警告，可继续 ⚠️${NC}"
    echo "建议修复警告项以获得最佳体验。"
    exit 0
fi
