---
name: windbg-reverse
description: Use for Windows debugging via the LAN WinDbg MCP (mcp-windbg): kernel/driver debugging (kd), crash dump triage (cdb), user-mode remote debugging, and kernel network stack (NDIS/WFP) reverse engineering.
---

# WinDbg 逆向调试（内核 / dump / 用户态）

## ACTION REQUIRED（读完后立刻执行）

1. `NOW`: 读取 `../field-journal/precedent-reverse.md`
2. `NOW`: 确认任务命中四场景之一（内核/驱动调试、crash dump 分诊、用户态远程调试、网络栈逆向）
3. `NEXT`: 读 `../tool-index.md` 确认 windbg-mcp 能力在线（servicePort 8765）；未注册 → bootstrap 能力名 `windbg-mcp`
4. `ACT`: 按工作流打开会话执行；结束 `MUST` 关闭会话

## 适用场景

- Windows 内核 / 驱动调试（`open_kd_session` + kd -k）
- BSOD / minidump / crash dump 分诊（`open_cdb_dump`）
- 用户态远程进程调试（`open_cdb_remote`，目标机 `cdb -server`）
- 内核态网络通信逆向（NDIS / WFP / Wsk / netio 栈）

## 与相邻 skill 分工

| 需求 | 优先 |
|------|------|
| 静态反编译二进制 | `ida-reverse/` / `ghidra-reverse/` |
| CTF kernel pwn / ROP | `pwn-chain/` |
| 恶意样本整体分诊 | `malware-analysis/`（内核态细节转本 skill） |
| 靶机 / 快照 / 实验环境 | `pve-lab/`（组合场景见其 kernel-debug-lab） |

## 工具链（windbg MCP，9 工具，会话制）

| MCP 工具 | 用途 |
|----------|------|
| `list_dumps` | 列出 dump 文件（默认注册表 dump 目录） |
| `open_cdb_dump` | 打开用户态 dump 并自动 `!analyze -v` |
| `open_cdb_remote` | 连接用户态远程调试服务（cdb -server） |
| `open_kd_session` | 连接内核目标（KDNET / 命名管道 / COM） |
| `run_cdb_command` / `run_kd_command` | 在会话中执行调试命令 |
| `close_cdb_session` / `close_kd_session` | 关闭会话释放资源 |
| `send_ctrl_break` | 打断运行中的活动会话 |

## 会话纪律（MUST）

- 一个分析任务一个会话；`session_id` 记入 timeline
- 结束 `MUST` 调 `close_cdb_session` / `close_kd_session`
- 长时间运行的目标用 `send_ctrl_break` 打断后再发命令
- 同一会话连续 2 次命令失败 → 换路径（静态 → `ida-reverse` / `ghidra-reverse`）

## 符号

`symbols_path` 参数或 `_NT_SYMBOL_PATH` 环境变量：

```text
srv*C:\symbols*https://msdl.microsoft.com/download/symbols
```

## 工作流

### 1. Crash dump 分诊

```text
□ list_dumps（可带 directory_path / recursive）
□ open_cdb_dump(dump_path, include_stack_trace=true, include_modules=true)
□ 自动 .lastevent + !analyze -v；按需补 kb / lm / ~（run_cdb_command）
□ 崩溃归因（驱动/模块/地址）走 Evidence→Finding→Path
```

### 2. 内核 / 驱动调试

```text
□ 前置：靶机已配内核调试串口/KDNET → 见 ../pve-lab/references/kernel-debug-lab.md
□ 先发现后连接：
  - 管道名：PVE 的 vm_config_get 读 serial0 配置（socket 模式）
  - 波特率：guest 侧 `bcdedit /dbgsettings` 读 baudrate，取不到则用惯例 115200
  - 或读 ../pve-lab/lab-profile.local.md 缓存，跳过发现步骤
□ open_kd_session(connection_string="com:port=com1,baud=115200", symbols_path=<符号路径>)
   注：PVE 环境下使用 COM1 端口，WinDbg 会显示 "Waiting to reconnect..."
□ pve: vm_start(vmid=300) → 启动靶机，WinDbg 自动连接
□ 调试循环（run_kd_command）：bp 断点 / g 执行 / k 栈 / lm 模块 / !drvobj
```

KDNET 变体：`net:port=50000,key=<key>`；物理串口：`com:port=COM1,baud=115200`。

### 3. 用户态远程调试

```text
□ 目标机启动调试服务：cdb -server tcp:port=5005 <program>
□ open_cdb_remote(connection_string="tcp:Port=5005,Server=<目标IP>")
□ run_cdb_command 执行；目标忙时 send_ctrl_break
```

### 4. 网络栈逆向

```text
□ 内核会话中定位过滤/NDIS 驱动：lm + !drvobj <DriverName> 2
□ 断发送路径（WskSend / NdisFSendNetBufferLists / 过滤驱动 FilterSendNetBufferLists）
□ 栈回溯 + 报文 buffer dump（db / dps），还原帧布局
□ 协议结构还原 → 交接 ../protocol-reverse/
```

## 建议下一步（选一个编号）

1. 继续当前会话深挖（新断点 / 单步 / 内存搜索）
2. 导出会话命令记录，生成阶段报告（docs-generator）
3. 交接静态反编译（ida-reverse / ghidra-reverse）交叉验证
4. 恢复靶机快照到干净态（pve-lab）
5. 暂停，我先确认前面的证据

## 语言行为契约

- 内部推理 / 工具选择：English
- 用户可见输出 / 报告 / 菜单：中文（双语标签 中文 / English）

## 参考

- `references/kd-cheatsheet.md`
- `references/crash-dump-workflow.md`
- `references/network-stack-debug.md`

## 路由上下文

**上游**: MASTER R41
**下游**: `protocol-reverse/`（协议还原）、`docs-generator/`（报告）
**同级**: `pve-lab/`（靶机环境）、`malware-analysis/`（样本分诊）

## 任务完成自检

- [ ] 所有 cdb/kd 会话是否已 close？
- [ ] 结论是否标注地址 / 模块 / 具体命令（可复现）？
- [ ] 是否基于 tool-index 确认的 MCP 端点执行？
- [ ] Checklist / journal 回写？
