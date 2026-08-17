# 内核调试实验室拓扑（vmware-lab × windbg-reverse）

## 拓扑

```text
分析机（AI 客户端）
  ├─ MCP: vmware-mcp  http://<lab-host>:8766/mcp/   ← 控制靶机
  └─ MCP: mcp-windbg  http://<lab-host>:8765/mcp/   ← 在 lab-host 上跑 kd.exe
                                      │
                              命名管道 \\.\pipe\<pipe>
                                      │
                              靶机 VM 串口（内核调试已启用）
```

kd 与 VMware Workstation 跑在同一台 lab-host，串口走命名管道。

## 标准流程（先发现、后连接）

```text
1. vm_list / vmrun_list            → 找到靶机 VM 名（vm_id / vmx 路径）
2. serial_query(vm_id)             → 读串口 backingPathName（管道名，实测可探测；
                                     output 另含 pipeEndPoint=server 等拓扑信息）
3. 波特率：宿主侧探测不到（命名管道无 baud 概念）
   - 权威：vmrun_run 在 guest 内跑 `bcdedit /dbgsettings` 读 baudrate
   - 缺省：惯例 115200（管道传输不受 baud 约束，名义值即可）
4. （缓存）读 lab-profile.local.md  → 跳过 1-3 加速；缺失不影响
5. vmrun_snapshot_take             → 拍干净态基线
6. vmrun_start                     → 拉起靶机（bcdedit /debug 已启用）
7. windbg: open_kd_session(connection_string="com:pipe,port=\\.\pipe\<step2 管道名>,baud=<step3 波特率>")
8. 调试循环（run_kd_command）
9. windbg: close_kd_session
10. vmrun_snapshot_revert           → 恢复干净态
```

## connection_string 三种格式（open_kd_session 实测支持）

| 方式 | 格式 | 适用 |
|------|------|------|
| 命名管道 | `com:pipe,port=\\.\pipe\com_1,baud=115200` | VMware 串口（默认拓扑） |
| KDNET | `net:port=50000,key=<32位key.逐字>` | Win8.1+，快 |
| 物理串口 | `com:port=COM1,baud=115200` | 实机调试 |

惯例默认值：管道 `com_1`、波特率 `115200`（仅当发现步骤拿不到值时用，且要向用户确认）。

## lab-profile.local.md 格式（gitignored，各机器自维护）

```markdown
# 本实验室环境值（不提交）
- target_vm: <VM 显示名>
- pipe_name: com_1
- baud: 115200
- windbg_mcp: http://192.168.100.175:8765/mcp/
- vmware_mcp: http://192.168.100.175:8766/mcp/
- host_only_net: VMnet1
```

## 靶机侧前置（一次性）

```text
bcdedit /debug on
bcdedit /dbgsettings serial debugport:1 baudrate:115200   # 串口方式
# 或 KDNET：bcdedit /dbgsettings net hostkey:<key>（记下 key/port）
```

VMware 侧：VM 设置 → 串口 → 输出到命名管道 `\\.\pipe\com_1`，"该端是服务器，另一端是应用程序"。
