#!/bin/bash
# PVE + WinDbg 内核调试环境验证脚本
# 在 lab-host (192.168.100.175) 上运行

set -e

echo "=== PVE + WinDbg 内核调试环境验证 ==="
echo ""

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

echo "1. MCP 服务端口检查"
echo "   检查 lab-host 上的 MCP 服务..."
if nc -z localhost 8765 2>/dev/null || nc -z 192.168.100.175 8765 2>/dev/null; then
    check_pass "WinDbg MCP (8765) 在线"
else
    check_fail "WinDbg MCP (8765) 离线"
fi

if nc -z localhost 8767 2>/dev/null || nc -z 192.168.100.175 8767 2>/dev/null; then
    check_pass "PVE MCP (8767) 在线"
else
    check_fail "PVE MCP (8767) 离线"
fi

echo ""
echo "2. PVE VM 300 配置检查"
if command -v qm &> /dev/null; then
    VM_STATUS=$(qm status 300 2>/dev/null | awk '/status:/ {print $2}')
    if [ -n "$VM_STATUS" ]; then
        check_pass "VM 300 状态: $VM_STATUS"
    else
        check_fail "VM 300 不存在或无法查询"
    fi

    SERIAL_CFG=$(qm config 300 2>/dev/null | grep -E "^serial0:")
    if [ -n "$SERIAL_CFG" ]; then
        check_pass "串口配置: $SERIAL_CFG"
    else
        check_warn "串口配置未找到"
    fi
else
    check_warn "qm 命令不可用（非 PVE 宿主）"
fi

echo ""
echo "3. AI 客户端配置检查"
if [ -f ~/.claude/mcp.json ]; then
    if grep -q "pve" ~/.claude/mcp.json 2>/dev/null; then
        check_pass "pve-mcp 已在 Claude MCP 配置中注册"
    else
        check_warn "pve-mcp 未在 Claude MCP 配置中找到"
    fi
    if grep -q "windbg" ~/.claude/mcp.json 2>/dev/null; then
        check_pass "windbg-mcp 已在 Claude MCP 配置中注册"
    else
        check_warn "windbg-mcp 未在 Claude MCP 配置中找到"
    fi
else
    check_warn "~/.claude/mcp.json 不存在"
fi

echo ""
echo "4. 测试 PVE MCP 基础调用"
echo "   测试命令: curl -X POST http://192.168.100.175:8767/mcp/ -H 'Content-Type: application/json' -H 'Accept: text/event-stream' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}'"
echo "   （需要 SSE 客户端或 AI 框架调用）"

echo ""
echo "5. 建议测试提示词"
echo "   测试 1: \"PVE VM ID 300 创建快照 pre-kd-test\""
echo "   测试 2: \"用 windbg 连接 PVE VM 300 内核调试\""
echo "   测试 3: \"PVE 靶机快照后调试驱动 BSOD\""

echo ""
echo "=== 验证完成 ==="
