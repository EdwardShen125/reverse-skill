# PVE + WinDbg 内核调试故障排除指南

本指南提供系统化的故障排查流程，涵盖 PVE + WinDbg 内核调试实验室的常见问题和解决方案。

## 快速诊断流程图

```text
问题出现
  ↓
MCP 服务健康？→ 否 → 检查服务进程、端口、日志
  ↓ 是
VM 状态正常？→ 否 → 检查电源、锁文件、磁盘空间
  ↓ 是
串口配置正确？→ 否 → 修正 serial0 配置
  ↓ 是
命名管道可访问？→ 否 → 检查管道基础设施
  ↓ 是
WinDbg MCP 在线？→ 否 → 重启 WinDbg MCP 服务
  ↓ 是
网络隔离配置正确？→ 否 → 调整网桥配置
  ↓
执行标准流程
```

## 症状索引

| 症状 | 可能原因 | 快速检查 | 见章节 |
|------|----------|----------|--------|
| MCP 调用超时 | 服务停止、网络不通 | curl 探测 | A.1 |
| VM 启动失败 | 资源不足、锁文件 | qm status、df -h | A.2 |
| WinDbg 连接超时 | 管道不可用、连接问题 | Test-Path pipe | A.3 |
| 快照操作失败 | 磁盘满、QEMU Agent | df -h、qm config | A.4 |
| 调试响应缓慢 | 资源争用、网络延迟 | top、ping | A.5 |
| 会话残留异常 | 清理不完整 | pgrep kd、qm status | A.6 |

## A. 系统级故障

### A.1 MCP 服务无响应

**症状**：
- `curl http://<lab-host>:8767/mcp/` 超时
- MCP 调用返回 5xx 错误或空响应

**诊断步骤**：

```bash
# 1. 检查端口监听
netstat -tuln | grep -E "8765|8767"
# 预期输出: tcp ... 8765 ... LISTEN
#          tcp ... 8767 ... LISTEN

# 2. 检查服务进程
ps aux | grep -E "8765|8767"
# 预期输出: python ... 8767 ... (pve-mcp)
#          python ... 8765 ... (windbg-mcp)

# 3. 检查服务日志
journalctl -u <service-name> -n 50 --since "1 hour ago"
# 关键词: ERROR, CRITICAL, Exception

# 4. 手动探测端点
curl -v http://<lab-host>:8767/mcp/ 2>&1 | head -20
# 预期: HTTP/1.1 406 Not Acceptable (SSE 端点正常行为)
#      或 HTTP/1.1 200 OK

# 5. 检查防火墙
iptables -L -n | grep -E "8765|8767"
# 如被阻止，添加规则
```

**解决方案**：

```bash
# 方案1: 重启服务（在 lab-host 上）
systemctl restart pve-mcp
systemctl restart windbg-mcp

# 方案2: 手动启动（如 systemd 失效）
cd /path/to/pve-mcp
nohup python -m pve_mcp.server --port 8767 > /var/log/pve-mcp.log 2>&1 &

# 方案3: 清理可能的端口占用
lsof -i :8767 | kill -9 <PID>  # 谨慎使用

# 方案4: 检查网络连通性
ping -c 3 <lab-host>
traceroute <lab-host>
```

### A.2 VM 启动失败

**症状**：
- `qm start <vmid>` 超时或返回错误
- VM 状态一直显示 "starting" 或 "unknown"

**诊断步骤**：

```bash
# 1. 检查 VM 当前状态
qm status "$VMID"
# 预期输出: status: running / stopped

# 2. 检查 QEMU 进程
ps aux | grep -i "qemu.*$VMID"
# 预期输出: qemu-system-x86_64 ... $VMID ...

# 3. 检查系统资源
free -h              # 内存检查
df -h /var/lib/vz    # 磁盘检查
top -bn1 | head -20  # CPU 检查

# 4. 检查锁文件
ls -la /var/lock/qemu-server/lock-$VMID.conf 2>/dev/null
# 可能残留锁文件导致启动失败

# 5. 检查 VM 配置有效性
qm config "$VMID" | head -20
# 查找语法错误或无效路径

# 6. 检查内核日志
dmesg | tail -50 | grep -i "kvm\|qemu"
journalctl -xe | tail -50
```

**解决方案**：

```bash
# 方案1: 清理残留锁文件
rm -f /var/lock/qemu-server/lock-$VMID.conf
rm -f /var/run/qemu-server/lock-$VMID.conf

# 方案2: 强制停止后重启
qm stop "$VMID" --skip-lock  # 跳过锁检查强制停止
sleep 3
qm start "$VMID"

# 方案3: 强制终止进程
qm kill "$VMID"               # 强制终止 VM
sleep 5
qm start "$VMID"

# 方案4: 扩展磁盘空间
lvextend -L +10G /dev/pve/data
# 或清理旧快照/日志

# 方案5: 减少内存分配
qm set "$VMID" -memory 2048   # 降配到 2GB

# 方案6: 检查并修复 VM 配置
qm config "$VMID" > /tmp/vm-$VMID.conf
# 编辑修复后导入
```

### A.3 WinDbg 连接超时

**症状**：
- `open_kd_session` 超时或返回 "连接失败"
- WinDbg 无法打开命名管道

**诊断步骤**：

```bash
# 1. 验证串口配置
qm config "$VMID" | grep serial0
# 预期输出: serial0: socket

# 验证命名管道（PowerShell，在 lab-host 上执行）

# 验证命名管道（PowerShell，在 lab-host 上执行）
Test-Path "\\.\\pipe\\com_1"
# 预期: True

[System.IO.Directory]::GetFiles('\\\\.\\pipe\\') | Where-Object { $_ -like "*com_1" }
# 预期: \\.\pipe\com_1

# 5. 测试管道连接（PowerShell）
$pipe = New-Object System.IO.Pipes.NamedPipeClientStream("\\.\\pipe\\com_1")
try {
    $pipe.Connect(5000)  # 5秒超时
    Write-Host "管道连接成功"
    $pipe.Close()
} catch {
    Write-Host "管道连接失败: $_"
}

# 6. 验证 WinDbg MCP 服务
curl -s http://<lab-host>:8765/mcp/ | head -1
```

**解决方案**：

```bash
# 方案1: 验证 VM 串口配置并修正
qm set "$VMID" -serial0 socket
qm config "$VMID" | grep serial0

# 方案2: 使用 TCP 模式替代命名管道
qm set "$VMID" -serial0 socket,server,nowait,port=50000
# WinDbg 连接字符串改为: com:port=<lab-host>:50000,target=kernel

# 方案3: 检查 WinDbg MCP 日志
# 在 lab-host 上查看 WinDbg MCP 日志文件
tail -50 /var/log/windbg-mcp.log
```

### A.4 快照操作失败

**症状**：
- `snapshot_create` 或 `snapshot_revert` 超时
- 快照操作返回 "磁盘空间不足" 或 "权限拒绝"

**诊断步骤**：

```bash
# 1. 检查磁盘空间
df -h /var/lib/vz
# 确保可用空间 >20GB

# 2. 检查快照列表
qm listsnapshot "$VMID"
# 查找冲突或损坏的快照

# 3. 检查 QEMU Agent 状态
qm config "$VMID" | grep agent
# agent: 1 表示启用

# 4. 测试 QEMU Agent 连通性
qm guest cmd "$VMID" ping
# 预期输出: pong

# 5. 检查存储配置
pvesm status
# 查看存储健康状态

# 6. 检查 I/O 性能
iostat -x 1 5
# 查看 I/O 等待时间
```

**解决方案**：

```bash
# 方案1: 清理旧快照释放空间
qm delsnapshot "$VMID" "old-snapshot-name"

# 方案2: 扩展存储空间
# LVM 方式
lvextend -L +50G /dev/pve/data
# ZFS 方式
zfs list
zfs set compression=lz4 pve/vm-100-disk-0

# 方案3: 停止 VM 后创建快照
qm stop "$VMID"
sleep 5
qm snapshot "$VMID" "pre-kd-debug-$(date +%Y%m%d)"
qm start "$VMID"

# 方案4: 删除损坏的快照
qm delsnapshot "$VMID" "broken-snapshot" --force

# 方案5: 禁用 QEMU Agent（如导致问题）
qm set "$VMID" -agent 0
```

### A.5 调试响应缓慢

**症状**：
- WinDbg 命令响应时间 >5 秒
- 断点命中延迟明显
- 单步执行卡顿

**诊断步骤**：

```bash
# 1. 检查系统资源
top -bn1 | head -15
# 关注 CPU 使用率、负载

# 2. 检查 VM 资源分配
qm config "$VMID" | grep -E "cores|cpu|memory|smbios"
# 确保分配足够资源

# 3. 检查网络延迟
ping -c 10 <lab-host>
# 预期: <1ms (局域网)

# 4. 检查串口波特率
# guest 侧（WinDbg 中执行）
.settings
# 确认波特率匹配 (115200)

# 5. 检查调试符号
!sym noisy
.reload /f
# 符号加载慢会导致响应慢

# 6. 检查 WinDbg 进程
ps aux | grep -i "kd\|windbg" | head -5
# 查看 CPU/内存占用
```

**解决方案**：

```bash
# 方案1: 提升 VM 资源分配
qm set "$VMID" -cores 4
qm set "$VMID" -cpu host
qm set "$VMID" -memory 4096

# 方案2: 优化串口参数
# guest 侧 bcdedit
bcdedit /dbgsettings serial debugport:1 baudrate:115200

# 方案3: 禁用不必要的符号加载
.sympath+ SRV*
.reload /f /n

# 方案4: 使用 KDNET 替代串口（更快）
bcdedit /debug off
bcdedit /dbgsettings net hostip:<lab-host-ip> port:50000 key:<your-key>
# WinDbg 连接: net:port=50000,key=<your-key>

# 方案5: 检查并优化 WinDbg MCP 性能
# 调整 WinDbg MCP 配置中的超时和缓冲设置
```

### A.6 会话残留异常

**症状**：
- 重新连接时提示 "会话已存在"
- VM 状态异常但进程仍在运行

**诊断步骤**：

```bash
# 1. 检查 WinDbg 残留进程
pgrep -f "kd.*com_1"
ps aux | grep -i "kd\|windbg"

# 2. 检查 VM 状态
qm status "$VMID"

# 3. 检查命名管道连接数
# PowerShell (lab-host)
Get-Process | Where-Object {$_.Handle -like "*pipe*"}

# 5. 检查日志文件
tail -50 /var/log/pve-kernel-debug.log
```

**解决方案**：

```bash
# 使用清理脚本
bash skills/pve-lab/scripts/cleanup-session.sh "$VMID"

# 手动清理流程
# 1. 终止 WinDbg 进程
pkill -9 -f "kd.*com_1"

# 2. 停止 VM
qm stop "$VMID" --skip-lock

# 3. 验证清理完成
pgrep -f "kd.*com_1" && echo "仍有 WinDbg 残留" || echo "WinDbg 已清理"
```

## B. 网络与连接问题

### B.1 网络隔离失效

**症状**：
- 靶机 VM 能够访问外网
- 隔离桥接网络配置不生效

**诊断步骤**：

```bash
# 1. 检查网桥配置
qm config "$VMID" | grep net0
# 预期: net0: bridge=vmbr0,...

# 2. 检查网桥状态
ip link show vmbr0
brctl show vmbr0

# 3. 检查防火墙规则
iptables -L -n | grep vmbr0

# 4. 在 guest 内测试网络连通性
ping 8.8.8.8  # 应该失败
```

**解决方案**：

```bash
# 方案1: 修正网桥配置
qm set "$VMID" -net0 bridge=vmbr0,firewall=1

# 方案2: 配置隔离网桥
# 在 PVE 宿主上创建隔离网桥
ip link add vmbr_isolated type bridge
ip addr add 192.168.200.1/24 dev vmbr_isolated
ip link set vmbr_isolated up

# 绑定 VM 到隔离网桥
qm set "$VMID" -net0 bridge=vmbr_isolated

# 方案3: 启用防火墙
qm set "$VMID" -net0 bridge=vmbr0,firewall=1
# 在 PVE 防火墙中配置出站规则
```

### B.2 MCP 服务网络不可达

**症状**：
- 从分析机无法访问 lab-host 上的 MCP 服务
- curl 连接超时

**诊断步骤**：

```bash
# 1. 测试基础连通性
ping -c 5 <lab-host>
traceroute -n <lab-host>

# 2. 测试端口可达性
nc -zv <lab-host> 8767
nc -zv <lab-host> 8765

# 3. 检查本地防火墙
iptables -L -n | grep -E "8765|8767"
ufw status (Ubuntu)

# 4. 检查 lab-host 防火墙
# SSH 到 lab-host 执行
iptables -L INPUT -n | grep -E "8765|8767"
```

**解决方案**：

```bash
# 方案1: 检查并启动 lab-host 上的服务
# SSH 到 lab-host
systemctl status pve-mcp
systemctl start pve-mcp

# 方案2: 添加防火墙规则（lab-host 上）
iptables -A INPUT -p tcp --dport 8767 -j ACCEPT
iptables -A INPUT -p tcp --dport 8765 -j ACCEPT
# 持久化
iptables-save > /etc/iptables/rules.v4

# 方案3: 检查 MCP 服务绑定地址
# 确保服务监听 0.0.0.0 而非 127.0.0.1
netstat -tuln | grep -E "8765|8767"
```

## C. 性能优化

### C.1 调试性能优化建议

**资源分配优化**：
```bash
# CPU 优化
qm set "$VMID" -cpu host,flags=+hv-passthrough
qm set "$VMID" -cores 4

# 内存优化
qm set "$VMID" -memory 4096

# I/O 优化
qm set "$VMID" -scsihw virtio-scsi-single
qm set "$VMID" -ssd 1
```

**串口通信优化**：
```bash
# 使用最高波特率
bcdedit /dbgsettings serial debugport:1 baudrate:115200

# 或使用 KDNET（推荐）
bcdedit /debug off
bcdedit /dbgsettings net hostip:192.168.100.175 port:50000 key:<auto>
```

**WinDbg 优化**：
```
# 禁用自动符号加载
.sympath SRV*
.reload /f /n

# 设置合理的超时
.settings Timeout=30

# 禁用不必要的输出
.soutn
```

### C.2 实验室资源监控

```bash
# 创建监控脚本
cat > /usr/local/bin/pve-lab-monitor.sh << 'EOF'
#!/bin/bash
LOG="/var/log/pve-lab-monitor.log"

echo "[$(date)] ===== PVE Lab Monitor =====" >> "$LOG"

# MCP 服务状态
for port in 8765 8767; do
    nc -z localhost $port && echo "✓ Port $port OK" >> "$LOG" || echo "✗ Port $port FAIL" >> "$LOG"
done

# 关键 VM 状态
for vmid in 300; do
    qm status "$vmid" >> "$LOG" 2>&1
done

# 磁盘空间
df -h /var/lib/vz >> "$LOG"

echo "" >> "$LOG"
EOF

chmod +x /usr/local/bin/pve-lab-monitor.sh

# 添加到 crontab，每5分钟执行
echo "*/5 * * * * /usr/local/bin/pve-lab-monitor.sh" | crontab -
```

## D. 应急处理

### D.1 完全重置流程

当所有其他方法失败时，执行完全重置：

**标准模式**（无备份）：
```bash
bash skills/pve-lab/scripts/emergency-reset.sh <vmid>
```

**安全模式**（推荐 - 先创建备份快照）：
```bash
bash skills/pve-lab/scripts/emergency-reset.sh --safe <vmid>
```

安全模式会在破坏性操作前创建备份快照，如需回滚：
```bash
qm rollback <vmid> emergency-backup-<timestamp>
```

**重置流程包括**：
1. 安全模式：创建备份快照（如启用）
2. 终止 WinDbg 进程
3. 优雅停止 VM（先 shutdown，超时后 stop，最后 kill）
4. 清理锁文件
5. 重新配置串口
6. 清理临时快照（跳过备份快照）
7. 创建新的基线快照

### D.2 保留证据的故障转储

```bash
# 在故障发生时收集诊断信息
mkdir -p /var/log/pve-debug-info/$(date +%Y%m%d-%H%M%S)
cd /var/log/pve-debug-info/$(date +%Y%m%d-%H%M%S)

# 系统状态
top -bn1 > top.txt
free -h > free.txt
df -h > df.txt
ps aux > ps.txt

# PVE 状态
qm status "$VMID" > qm-status.txt
qm config "$VMID" > qm-config.txt
qm listsnapshot "$VMID" > snapshots.txt

# 网络状态
netstat -tuln > netstat.txt
iptables -L -n > iptables.txt

# 进程信息
pgrep -af "kd" > kd-processes.txt

# 日志
journalctl -xe > journal.txt
tail -100 /var/log/syslog > syslog-tail.txt

# 打包
cd /var/log/pve-debug-info
tar czf pve-debug-$(date +%Y%m%d-%H%M%S).tar.gz $(basename $PWD)
```

## E. 联系支持前检查清单

在寻求技术支持前，请收集以下信息：

- [ ] 运行 `check-dependencies.sh` 并保存输出
- [ ] 记录完整的错误消息（包括时间戳）
- [ ] 执行故障转储脚本并保存输出
- [ ] 说明复现步骤的详细流程
- [ ] 提供配置文件：`qm config "$VMID"` 输出
- [ ] 提供日志文件：MCP 服务日志、系统日志
- [ ] 说明已尝试的解决方案及其结果

## 常用命令速查

| 任务 | 命令 |
|------|------|
| 检查 VM 状态 | `qm status "$VMID"` |
| 查看串口配置 | `qm config "$VMID" \| grep serial0` |
| 测试命名管道 | `Test-Path "\\\.\\pipe\\com_1"` |
| 测试 MCP 服务 | `curl http://<lab-host>:8767/mcp/` |
| 执行依赖检查 | `bash skills/pve-lab/scripts/check-dependencies.sh $VMID` |
| 执行会话清理 | `bash skills/pve-lab/scripts/cleanup-session.sh $VMID` |
| 查看快照列表 | `qm listsnapshot "$VMID"` |
| 创建快照 | `qm snapshot "$VMID" "name"` |
| 恢复快照 | `qm rollback "$VMID" "snapshot-name"` |
| 删除快照 | `qm delsnapshot "$VMID" "snapshot-name"` |
