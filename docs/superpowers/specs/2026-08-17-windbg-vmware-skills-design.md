# 设计文档：新增 windbg-reverse / vmware-lab 双 skill

- 日期：2026-08-17
- 状态：已获用户批准的设计（本文件为实现前规格）
- 集成深度：方案 C（完整新增 skill + manifest 登记 + 路由 + 测试）

## 1. 背景与目标

用户在内网 192.168.100.175 部署了两个 MCP server，需要让本 skill 路由包能：

1. 通过关键词自动路由到对应工作流
2. 在 tool-index capability 视图中可见（含端口健康检查）
3. 通过仓库分发到其他机器后，bootstrap 能自动把 MCP URL 注册进各机器客户端配置

### MCP 端点（已探测确认在线）

| Server | 版本 | URL | 响应格式 |
|---|---|---|---|
| mcp-windbg | 1.29.0 | `http://192.168.100.175:8765/mcp/` | JSON (uvicorn) |
| vmware-mcp | 1.29.0 | `http://192.168.100.175:8766/mcp/` | SSE (uvicorn) |

## 2. 两个 skill 的定位与边界

### skills/windbg-reverse/

Windows 调试工作流，四个场景（按用户需求）：

1. **内核/驱动调试** — `open_kd_session` → `run_kd_command`（kd -k 连接内核目标）
2. **crash dump 分析** — `list_dumps` → `open_cdb_dump`（cdb 用户态分诊）→ `run_cdb_command`
3. **用户态进程调试** — `open_cdb_remote`（连接远程调试服务）→ `run_cdb_command` / `send_ctrl_break`
4. **网络通信逆向** — 内核会话中调试 NDIS/WFP/Wsk/netio 栈，与 protocol-reverse 下游衔接

**会话纪律（SKILL.md 硬性要求）**：所有会话（cdb/kd）用完 `MUST` 调 `close_cdb_session`/`close_kd_session`；长时间运行的目标用 `send_ctrl_break` 打断；一个分析任务建议单会话，避免 session_id 混乱。

**真实工具面（9 个）**：list_dumps, open_cdb_dump, open_cdb_remote, open_kd_session, run_cdb_command, run_kd_command, close_cdb_session, close_kd_session, send_ctrl_break

### skills/vmware-lab/

实验室基础设施 skill，三个场景：

1. **分析靶机环境** — 快照纪律（分析前必拍、恶意样本后必 revert）、host-only 隔离网
2. **实验环境编排** — 模板部署（template_deploy）、克隆（vmrun_clone / snapshot_clone）、批量建机
3. **通用 VM 控制** — 电源、guest 文件传输、guest 内执行程序、截图、键入

**三层 API 优先级规则（SKILL.md 硬性要求，防 AI 乱选）**：

| 操作类型 | 首选层 | 工具示例 |
|---|---|---|
| guest 内操作（文件/进程/执行） | vmrun 层 | vmrun_run, vmrun_copy_to, vmrun_ps |
| 快照 | vmrun 层（vmcli 备选） | vmrun_snapshot_take/revert |
| VM 生命周期/克隆 | REST 层 | vm_create, vm_delete, vm_power_set |
| 网络拓扑/端口转发 | REST 层 | network_list, network_portforward_set |
| 硬件配置（CPU/内存/网卡/磁盘） | vmcli 层 | chipset_set_cpu, ethernet_set_network, nvme_* |

**隔离纪律**：恶意样本分析 `MUST` 确认网卡处于 host-only/无外联（network_list + ethernet_query 校验）后才投递样本；快照 revert 是"清污染"唯一可靠手段。

## 3. 目录结构

```
skills/windbg-reverse/
├── SKILL.md
└── references/
    ├── kd-cheatsheet.md          # kd/cdb 常用命令：断点/符号/!analyze/ndiskd/wfp
    ├── crash-dump-workflow.md    # BSOD/minidump 分诊流程
    └── network-stack-debug.md    # NDIS/WFP/Wsk 栈调试方法论

skills/vmware-lab/
├── SKILL.md
├── lab-profile.local.md         # 本实验室具体值（VM名/管道名/baud），gitignored
└── references/
    ├── snapshot-hygiene.md       # 快照纪律与污染恢复
    ├── isolated-network.md       # host-only 隔离网与端口转发
    └── kernel-debug-lab.md       # 内核调试实验室拓扑（与 windbg-reverse 组合场景）
```

### 具体值分层原则（用户确认）

skill 正文是随仓库分发的方法论，`MUST NOT` 写死单机环境值：

| 层 | 内容 | 是否提交 |
|---|---|---|
| SKILL.md / references | 方法论 + 通用惯例默认值（管道 `com_1`、波特率 `115200`）+ 自动发现流程 | 提交 |
| `lab-profile.local.md` | 单实验室具体值：VM 名、实际管道名/baud、MCP 地址 | 不提交（加 .gitignore 条目，各机器自维护） |
| 运行时发现 | MCP 自枚举：`vm_list`/`vmrun_list` 找靶机、`serial_query` 读串口管道配置、`network_list` 查隔离网 | 无需维护 |

**先发现、后连接**：工作流优先运行时枚举；lab-profile 仅作缓存加速，缺失不影响功能。

### 内核调试组合场景（两 skill 桥接）

```
pve-lab: snapshot_create（拍照）→ 启动顺序注意（见下文）
    ↓ vm_list / vm_config_get 自动发现 VM ID 与波特率（或读 lab-profile.local.md）
windbg-reverse: open_kd_session(connection_string="com:port=com1,baud=115200")
    ↓ WinDbg 显示 "Waiting to reconnect..." 状态
pve-lab: vm_start(vmid=300) → 启动靶机，WinDbg 自动连接
    ↓ 调试循环：bp 断点 / g 执行 / !analyze
    ↓ 结束
windbg-reverse: close_kd_session → pve-lab: snapshot_revert（恢复干净态）
```

`open_kd_session.connection_string` 三种支持格式（实测）：KDNET `net:port=50000,key=...`、COM1 串口 `com:port=com1,baud=115200`（PVE 环境）、物理串口 `com:port=COM1,baud=115200`。

**重要**：PVE 环境下启动顺序必须为：WinDbg 先启动并进入等待状态 → 然后启动 PVE VM，WinDbg 才能自动连接。

两个 SKILL.md 均含（CONTRIBUTING.md 3.1-3.4 硬性块）：

- frontmatter（name/description）
- `ACTION REQUIRED`（第一步读 `../field-journal/precedent-reverse.md`）
- 语言行为契约（内部推理 English，用户输出中文）
- 每阶段末尾"建议下一步"3-6 项编号菜单
- 末尾"任务完成自检"

## 4. 路由设计

### routing.json 新增（编号接现有最大值之后，实施时确认）

**windbg-reverse 路由** 关键词：

```
windbg|\bkd\b|\bcdb\b|crash.?dump|minidump|dump.?分析|蓝屏|bsod|内核.?调试|驱动.?逆向|driver.?reverse|!analyze|ndiskd
```

消解：`kernel.?pwn` 归 R17（pwn-chain）不动；CTF 内核题语境靠 exclude "ctf|pwn|rop" 排除到 R17。

**vmware-lab 路由** 关键词：

```
vmware|vsphere|esxi|vmrun|快照|snapshot|靶机|虚拟机.?环境|host.?only|vm.?编排|实验环境
```

消解：裸"沙箱/sandbox"归 R9（malware）不动；VMware 仅在靶机/快照/实验环境语境命中。

### 联动文件（全部同步改）

1. `skills/config/routing.json` — 2 条 route + priority 数组
2. `skills/MASTER-ROUTING.md` — 优先级表（与 priority 一致，verify-routing-coherence 校验）
3. `skills/routing.md` — 三轴表各加行
4. `skills/SKILL.md` — 模块表加 2 行
5. `RULES.md` — 触发关键词加 windbg/蓝屏/快照/靶机 等
6. `skills/tests/routing-benchmark.json` — 新增 8-10 条用例（含 R6/R9/R17 边界）

## 5. MCP 注册（manifest 与客户端两层）

### 仓库层（随仓库分发到其他机器）

`skills/scripts/bootstrap-manifest.json` 与 `kali/scripts/bootstrap-manifest.json` 各加 2 条：

```json
{
  "name": "windbg-mcp",
  "bootstrapKind": "local-http-mcp",
  "mcpNames": ["windbg"],
  "mcpUrl": "http://192.168.100.175:8765/mcp/",
  "servicePort": 8765,
  "docsUrl": "",
  "canAutoInstall": false,
  "verificationMode": "service-or-registration",
  "manualInstallHint": "内网 MCP：确保 192.168.100.175:8765 可达；服务由内网调试机提供"
}
```

vmware-mcp 同构（8766 端口，mcpNames ["vmware"]）。

- `canAutoInstall: false`：bootstrap 不安装服务，只注册 URL 到本机客户端 mcp.json + 端口探测
- 地址含内网 IP：本仓库为用户私有二开用途，可接受；若将来公开需换占位符（用户已知悉）
- SSE 响应格式（vmware）不影响注册，仅 URL

### 本机层

当前机器可直接在 `~/.claude/mcp.json` 登记（bootstrap 亦会自动写）。

## 6. ToolDiscovery / refresh-tool-index 接入

- `skills/scripts/lib/ToolDiscovery.ps1` 与 `kali/scripts/lib/tool-discovery.sh`：按现有 MCP server 条目格式登记（实施时参照 idalib-mcp / anything-analyzer 的写法）
- `refresh-tool-index.ps1` 的 `$scriptRefs`：windbg/vmware → 对应 skill 的 SKILL.md

## 7. 验证清单

```bash
pwsh skills/scripts/verify-routing-coherence.ps1
pwsh skills/scripts/test-routing.ps1
pwsh skills/scripts/extract-summaries.ps1        # 重新生成 INDEX.md
bash skills/scripts/refresh-tool-index.sh         # macOS 本机验证 tool-index 出现两个新能力
```

CI 门禁：路由回归（含新用例）、coherence、INDEX 新鲜度、JSON 校验全部通过。

## 8. 非目标（明确不做）

- 不为 130 个 vmware 工具逐一写文档，references/ 只写纪律与选层规则
- 不修改 CTF-Sandbox-Orchestrator（GPLv3）
- 不实现 dump 的自动符号服务器配置（SKILL.md 给 `_NT_SYMBOL_PATH` 指引即可）
