# PVE + WinDbg 内核调试集成测试报告

**测试时间**: 2026-08-27
**测试范围**: PVE MCP (8767) + WinDbg MCP (8765) + VM ID 300 内核调试

## 配置验证

### 1. MCP 服务状态

| 服务 | 端口 | 状态 | 传输模式 |
|------|------|------|----------|
| WinDbg MCP | 8765 | ✅ Online (406 SSE) | Server-Sent Events |
| PVE MCP | 8767 | ✅ Online (406 SSE) | Server-Sent Events |
| VMware MCP | 8766 | - | - (被 PVE 替代) |

### 2. 路由配置

| 路由 ID | 标签 | Skill | 关键词测试 |
|---------|------|-------|-----------|
| R41 | WinDbg 调试 | windbg-reverse | ✅ windbg/kd/cdb/dump/蓝屏 |
| R43 | PVE 实验室 | pve-lab | ✅ pve/proxmox/qm/vmid |

### 3. 边界测试

| 测试用例 | 期望路由 | 结果 |
|----------|----------|------|
| PVE 靶机 快照 恶意样本分析 | R43 | ✅ 不与 R42 (vmware) 冲突 |
| vmware 靶机 快照 恶意样本环境 | R42 | ✅ 不受 R43 影响 |
| windbg 调试 驱动 逆向 | R41 | ✅ 独立命中 |

## 内核调试流程验证

### 标准流程（PVE VM ID 300）

```
□ Step 1: vm_list → 发现 VM ID 300
□ Step 2: vm_config_get(vmid=300, key="serial0") → 确认 socket 模式
□ Step 3: snapshot_create(vmid=300, name="pre-kd-debug-20260827")
□ Step 4: vm_start(vmid=300)
□ Step 5: windbg: open_kd_session(connection_string="com:pipe,port=\\\\.\\pipe\\com_1,baud=115200")
□ Step 6: 调试循环 (run_kd_command)
□ Step 7: windbg: close_kd_session
□ Step 8: snapshot_revert(vmid=300, snapname="pre-kd-debug-20260827")
```

### WinDbg 连接字符串选项

| 方式 | 格式 | 适用场景 |
|------|------|----------|
| 命名管道（socat 转接） | `com:pipe,port=\\.\pipe\com_1,baud=115200` | PVE socket → Windows 管道 |
| TCP 直连 | `com:port=<host>:50000,target=kernel` | PVE TCP socket 模式 |
| KDNET | `net:port=50000,key=<32位key>` | Win8.1+ 内核调试（最快） |

## 实际测试步骤

### 在 Lab Host (192.168.100.175) 上执行

```bash
# 1. 检查 socat 转接状态
ps aux | grep socat
# 预期: socat UNIX-CONNECT:/var/run/qemu-server/300.serial0 PIPE:\\.\pipe\com_1

# 2. 检查 PVE VM 串口配置
qm config 300 | grep serial
# 预期: serial0: socket

# 3. 检查 VM 状态
qm status 300
# 预期: status: running 或 stopped

# 4. 检查命名管道（Windows 侧）
# powershell: [System.IO.Directory]::GetFiles("\\.\pipe\")
# 预期: 包含 com_1 管道
```

### AI 客户端测试

```text
测试提示词 1（PVE 路由）:
"PVE VM ID 300 创建一个快照用于内核调试"
期望: 路由到 R43 (pve-lab)，调用 snapshot_create

测试提示词 2（WinDbg 路由）:
"用 windbg 调试 VM 300 内核，断点在 nt!NtCreateFile"
期望: 路由到 R41 (windbg-reverse)，调用 open_kd_session

测试提示词 3（组合场景）:
"PVE 靶机快照后，用 windbg 调试驱动 BSOD"
期望: 先 R43 (pve-lab) 创建快照，后 R41 (windbg-reverse) 调试
```

## 集成检查清单

### 文件同步

- [x] `skills/scripts/bootstrap-manifest.json` 包含 pve-mcp
- [x] `kali/scripts/bootstrap-manifest.json` 包含 pve-mcp
- [x] `skills/scripts/refresh-tool-index.ps1` 包含 pve-mcp
- [x] `RULES.md` MCP 服务表包含 pve
- [x] `RULES_zh.md` MCP 服务表包含 pve
- [x] `skills/config/routing.json` 包含 R43 路由
- [x] `skills/MASTER-ROUTING.md` 优先级表包含 R43
- [x] `skills/routing.md` 三轴表包含 PVE 条目
- [x] `skills/tests/routing-benchmark.json` 包含 PVE 测试用例
- [x] `skills/SKILL.md` 模块表包含 pve-lab
- [x] `skills/INDEX.md` 包含 pve-lab 条目

### Skill 完整性

- [x] `skills/pve-lab/SKILL.md` 完整（含 ACTION REQUIRED、工作流、纪律）
- [x] `skills/pve-lab/references/kernel-debug-lab.md` 完整（含串口配置）
- [x] `skills/pve-lab/references/snapshot-hygiene.md` 完整
- [x] `skills/pve-lab/references/isolated-network.md` 完整
- [x] `skills/pve-lab/lab-profile.local.md` 模板创建
- [x] `.gitignore` 排除 lab-profile.local.md

## 下一步建议

1. **确认 socat 转接运行**: 在 lab-host 上检查 socat 进程
2. **测试 PVE MCP 工具**: 通过 AI 客户端调用 pve-mcp 的 vm_list/vm_config_get
3. **测试 WinDbg 连接**: 通过 AI 客户端调用 windbg-mcp 的 open_kd_session
4. **验证完整流程**: 执行"标准流程"8 步骤
5. **更新 lab-profile.local.md**: 填入实际 VM ID 300 的配置值

## 已知限制

1. PVE MCP 使用 SSE 传输，无法通过普通 HTTP 探测获取工具列表
2. macOS 客户端无法直接测试 Windows 命名管道 `\\.\pipe\com_1`
3. 实际工具调用需要在 Windows lab-host 或 AI 客户端环境测试

## 结论

✅ **配置验证通过**: 路由、MCP 注册、Skill 文档全部就绪
⏳ **待实际测试**: 需要在 lab-host 上验证 PVE MCP 工具调用和 WinDbg 连接
