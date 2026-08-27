# 内核调试实验室拓扑（pve-lab × windbg-reverse）

## 拓扑

```text
分析机（AI 客户端）
  ├─ MCP: pve-mcp      http://<lab-host>:8767/mcp/   ← 控制 PVE 靶机
  └─ MCP: mcp-windbg   http://<lab-host>:8765/mcp/   ← 在 lab-host 上跑 kd.exe
                                      │
                              QEMU 串口 Socket
                              /var/run/qemu-server/<vmid>.serial0
                                      │
                              靶机 VM 串口（内核调试已启用）
```

kd 与 PVE 跑在同一台 lab-host，串口走 QEMU Socket。

## 状态验证（生产环境强制预检）

**每次会话前必须执行状态验证，失败不得继续。**

### 1. MCP 服务健康检查

```bash
# PVE MCP (8767) - 控制平面可用性
curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://<lab-host>:8767/mcp/" | grep -E "406|200"
# 返回 406 是 SSE 端点正常行为，200 也可接受

# WinDbg MCP (8765) - 调试服务可用性
curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://<lab-host>:8765/mcp/" | grep -E "406|200"
```

**失败恢复**：检查 lab-host 上的 MCP 服务进程，必要时重启。

### 2. VM 状态验证

```bash
# 检查 VM 存在性
qm status <vmid> 2>/dev/null || { echo "VM $VMID 不存在"; exit 1; }

# 检查当前电源状态
VM_STATUS=$(qm status "$VMID" 2>/dev/null | awk '/status:/ {print $2}')
case "$VM_STATUS" in
    running)
        echo "警告: VM 已运行，检查是否有并发调试会话"
        pgrep -f "kd.*com_1" && { echo "错误: 现有 WinDbg 会话冲突"; exit 1; }
        ;;
    stopped)
        echo "VM 已停止，可安全启动"
        ;;
    *)
        echo "VM 状态异常: $VM_STATUS"
        exit 1
        ;;
esac
```

### 3. 串口配置验证

```bash
# 验证串口配置为 socket 模式
SERIAL_CFG=$(qm config "$VMID" 2>/dev/null | grep -E "^serial0:" || echo "")
if [ -z "$SERIAL_CFG" ]; then
    echo "错误: 未找到串口配置 (serial0)"
    exit 1
fi

if ! echo "$SERIAL_CFG" | grep -q "socket"; then
    echo "错误: 串口未配置为 socket 模式: $SERIAL_CFG"
    exit 1
fi

echo "串口配置正确: $SERIAL_CFG"
```

### 4. 命名管道验证（Windows 侧）

```powershell
# 验证命名管道可用性
Test-Path "\\.\\pipe\\com_1"
# 预期输出: True
```

**失败处理**：如管道不可用，联系管理员检查基础设施配置。

### 5. 快照冲突检测

```bash
# 检查是否存在可能冲突的快照
SNAPSHOTS=$(qm listsnapshot "$VMID" 2>/dev/null | grep -E "^$VMID-" || "")
if [ -n "$SNAPSHOTS" ]; then
    echo "警告: 发现现有快照，可能冲突:"
    echo "$SNAPSHOTS"
    echo "建议: 手动清理或重命名冲突快照"
fi
```

### 6. 网络隔离验证（恶意样本分析时重要）

```bash
# 验证网卡配置是否使用隔离桥接
FIRST_NIC=$(qm config "$VMID" 2>/dev/null | grep -E "^net0:" | head -1 || "")
if [ -n "$FIRST_NIC" ]; then
    echo "网卡配置: $FIRST_NIC"
    if echo "$FIRST_NIC" | grep -q "bridge"; then
        BRIDGE=$(echo "$FIRST_NIC" | grep -oP 'bridge=\K[^,]+' || echo "unknown")
        if [ "$BRIDGE" != "vmbr0" ] && [ "$BRIDGE" != "unknown" ]; then
            echo "警告: 非隔离桥接网络: $BRIDGE"
        fi
    fi
fi
```

### 7. 综合预检脚本

使用 `skills/pve-lab/scripts/check-dependencies.sh <vmid>` 执行全部检查。

**退出码**：0=通过，1=关键失败（禁止继续），0+警告=谨慎继续。

## 标准流程（先发现、后连接）

```text
1. vm_list                         → 找到靶机 VM ID（如 300）
2. vm_config_get(vm_id, "serial0") → 读串口配置（确认 socket 模式）
3. 波特率：通常 115200（guest 侧 bcdedit 配置）
4. （缓存）读 lab-profile.local.md → 跳过 1-3 加速；缺失不影响
5. snapshot_create                 → 拍干净态基线
6. vm_start                        → 拉起靶机（bcdedit /debug 已启用）
7. windbg: open_kd_session(connection_string="com:pipe,port=\\\\.\\pipe\\com_1,baud=115200")
   注：假设命名管道基础设施已就绪
8. 调试循环（run_kd_command）
9. windbg: close_kd_session
10. snapshot_revert                → 恢复干净态
```

## connection_string 与 Socket 转接

### PVE 串口 Socket 配置

在 PVE VM 配置中设置：
```bash
# 方法1：通过 Web UI
VM Hardware → Serial Port → Serial0 → Socket mode

# 方法2：通过 CLI/API
qm set <vmid> -serial0 socket
```

### 命名管道连接（WinDbg 需要）

WinDbg 通过命名管道连接到靶机串口。

**前置条件**（用户保证）：
- 命名管道 `\\.\pipe\com_1` 已可用
- 管道已正确连接到 PVE VM 串口

**可用性验证**：
```powershell
# Windows PowerShell 验证
Test-Path "\\.\\pipe\\com_1"
# 预期输出: True
```

**替代方案**：使用 TCP socket 模式（无需命名管道）
```bash
# PVE 侧配置（TCP socket）
qm set <vmid> -serial0 socket,server,nowait,port=50000

# WinDbg 连接字符串
com:port=<lab-host>:50000,target=kernel
```

### 三种格式（open_kd_session 实测支持）

| 方式 | 格式 | 适用 |
|------|------|------|
| 命名管道（标准） | `com:pipe,port=\\.\pipe\com_1,baud=115200` | 使用 COM1 管道（基础设施保证） |
| TCP 直连 | `com:port=<host>:50000,target=kernel` | PVE TCP socket 模式 |
| KDNET | `net:port=50000,key=<32位key>` | Win8.1+，最快 |

惯例默认值：波特率 115200。

## lab-profile.local.md 格式（gitignored，各机器自维护）

```markdown
# 本实验室环境值（不提交）
- target_vmid: 300
- socket_path: /var/run/qemu-server/300.serial0
- pipe_name: com_1
- baud: 115200
- windbg_mcp: http://192.168.100.175:8765/mcp/
- pve_mcp: http://192.168.100.175:8767/mcp/
- isolated_bridge: vmbr0
```

## 靶机侧前置（一次性）

```text
bcdedit /debug on
bcdedit /dbgsettings serial debugport:1 baudrate:115200   # 串口方式
# 或 KDNET：bcdedit /dbgsettings net hostkey:<key>（记下 key/port）
```

PVE 侧：VM Hardware → Serial Port (Serial0) → Mode: Socket

## 快照与内核调试联动

```text
□ 分析前：snapshot_create(name="pre-kd-debug-<日期>")
□ 内核调试中：Windbg 连接 → 断点 → 分析
□ 异常恢复：snapshot_revert(snapshot="pre-kd-debug-<日期>")
□ 关闭靶机：vm_stop(vm_id)
```

快照 revert 后，VM 配置保持不变（serial0 配置不受影响），但 guest 内状态完全恢复。

## 超时与重试配置（生产环境推荐）

### 超时设置

```bash
# MCP 调用超时
MCP_TIMEOUT=30s           # MCP 服务调用最大等待时间
VM_START_TIMEOUT=120s     # VM 启动最大等待时间
DEBUG_CONNECT_TIMEOUT=60s   # WinDbg 连接最大等待时间

# PowerShell 示例
$MCP_TIMEOUT = New-TimeSpan -Seconds 30
$VM_START_TIMEOUT = New-TimeSpan -Seconds 120
```

### 重试策略

```bash
# 指数退避重试（Exponential Backoff）
MAX_RETRIES=3
BASE_DELAY=5s             # 初始延迟 5 秒
MAX_DELAY=60s             # 最大延迟 60 秒

# 伪代码
for i in $(seq 1 $MAX_RETRIES); do
    if operation_with_timeout; then
        break
    fi
    delay=$(min($BASE_DELAY * 2^($i-1), $MAX_DELAY))
    sleep $delay
done
```

### 操作建议超时

| 操作 | 建议超时 | 重试次数 |
|------|----------|----------|
| vm_start | 120s | 2 |
| vm_stop | 60s | 2 |
| snapshot_create | 90s | 1 |
| snapshot_revert | 60s | 2 |
| open_kd_session | 60s | 3 |
| run_kd_command | 30s | 1 |

## 故障恢复流程（常见失败场景）

### 场景1: 命名管道不可用

**症状**：WinDbg 连接超时，无法打开命名管道

**诊断**：
```powershell
# 验证命名管道可用性
Test-Path "\\.\\pipe\\com_1"
# 预期: True

# 列出调试相关管道
[System.IO.Directory]::GetFiles('\\\\.\\pipe\\') | Where-Object { $_ -like "*com_1" }
```

**处理**：如管道不可用，联系管理员检查基础设施配置。

### 场景2: VM 启动超时

**症状**：vm_start 调用超时，VM 状态一直是 "starting"

**诊断**：
```bash
# 检查 VM 状态
qm status "$VMID"

# 检查 QEMU 进程
ps aux | grep -i "qemu.*$VMID"

# 检查系统资源
free -h
df -h
```

**恢复**：
```bash
# 1. 强制停止 VM
qm stop "$VMID" --skip-lock  # 跳过锁检查
# 或
qm kill "$VMID"               # 强制终止

# 2. 检查并清理锁文件
rm -f /var/lock/qemu-server/lock-$VMID.conf

# 3. 重新启动
qm start "$VMID"

# 4. 验证启动成功
sleep 10
qm status "$VMID" | grep "running"
```

### 场景3: WinDbg 连接失败

**症状**：open_kd_session 超时或返回连接错误

**诊断**：
```bash
# 1. 验证串口配置
qm config "$VMID" | grep serial0

# 2. 验证命名管道（PowerShell）
Test-Path "\\.\\pipe\\com_1"

# 3. 验证 WinDbg MCP 服务
curl -s "http://<lab-host>:8765/mcp/"
```

**恢复**：
```bash
# 1. 确保 VM 已启动并进入调试模式
qm status "$VMID" | grep running

# 2. 验证命名管道可用
# PowerShell: Test-Path "\\.\\pipe\\com_1"

# 3. 在 WinDbg MCP 上尝试重新打开会话
# windbg: close_kd_session()  # 先关闭可能存在的僵尸会话
# windbg: open_kd_session(connection_string="...")
```

### 场景4: 快照操作失败

**症状**：snapshot_create 或 snapshot_revert 超时

**诊断**：
```bash
# 检查快照列表
qm listsnapshot "$VMID"

# 检查磁盘空间
df -h /var/lib/vz

# 检查 QEMU Agent
qm config "$VMID" | grep agent
```

**恢复**：
```bash
# 1. 确保不在运行中状态时创建快照
qm stop "$VMID"
sleep 5

# 2. 删除可能损坏的快照
qm delsnapshot "$VMID" "broken-snapshot"

# 3. 重新创建快照
qm snapshot "$VMID" "pre-kd-debug-$(date +%Y%m%d-%H%M%S)"

# 4. 验证
qm listsnapshot "$VMID" | grep "pre-kd-debug"
```

### 场景5: MCP 服务无响应

**症状**：MCP 调用超时或返回 5xx 错误

**诊断**：
```bash
# 检查服务进程（在 lab-host 上）
ps aux | grep -E "8765|8767"

# 检查端口监听
netstat -tuln | grep -E "8765|8767"

# 检查服务日志
journalctl -u <service-name> -n 50
```

**恢复**：
```bash
# 在 lab-host 上重启 MCP 服务
systemctl restart windbg-mcp   # 或对应的服务名
systemctl restart pve-mcp

# 验证服务恢复
curl -s "http://localhost:8765/mcp/" | head -1
curl -s "http://localhost:8767/mcp/" | head -1
```

## 会话清理机制（防止资源泄漏）

### 调试会话结束后必须执行

```bash
# 1. 关闭 WinDbg 会话
windbg: close_kd_session()

# 2. 停止靶机 VM
vm_stop(vm_id)

# 3. 记录会话结束时间
echo "Session ended at $(date)" >> /var/log/pve-kernel-debug.log
```

### 异常清理脚本

```bash
# 标准模式（有活动会话时会提示确认）
bash skills/pve-lab/scripts/cleanup-session.sh <vmid>

# 强制模式（跳过确认直接清理）
bash skills/pve-lab/scripts/cleanup-session.sh --force <vmid>
```

## 生产环境最佳实践

### 定期健康检查

```bash
# 添加到 crontab，每小时执行
0 * * * * /path/to/skills/pve-lab/scripts/check-dependencies.sh 300 >> /var/log/pve-health.log 2>&1
```

### 监控关键指标

- MCP 服务可用性（8765, 8767）
- 命名管道可访问性
- VM 状态异常
- 磁盘空间充足性

### 告警阈值建议

| 指标 | 警告 | 严重 |
|------|------|------|
| MCP 服务响应时间 | >3s | >10s |
| VM 启动时间 | >90s | >180s |
| 磁盘使用率 | >70% | >85% |
| 命名管道可用性 | 间歇性不可用 | 持续不可用 |
