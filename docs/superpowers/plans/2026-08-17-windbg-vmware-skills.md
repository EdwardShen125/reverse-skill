# windbg-reverse / vmware-lab 双 Skill 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `windbg-reverse` 与 `vmware-lab` 两个 skill，接入内网 MCP（192.168.100.175:8765 / 8766），完成路由、manifest、索引、测试全套联动。

**Architecture:** 纯 markdown + JSON 配置改动，无代码逻辑。测试即仓库自带脚本套件（test-routing / verify-routing-coherence / verify-doc-facts / test-bootstrap-supply-chain / extract-summaries -Check）。TDD 体现为：先加 routing-benchmark 失败用例，再实现路由使其通过。

**Tech Stack:** routing.json (regex 评分路由)、bootstrap-manifest.json (local-http-mcp)、PowerShell/Bash 校验脚本。

**设计规格:** `docs/superpowers/specs/2026-08-17-windbg-vmware-skills-design.md`

---

## 环境准备（Task 0）

- [ ] **Step 0.1: 确认 pwsh 可用**

Run: `command -v pwsh && pwsh --version`
Expected: 输出版本号。若无输出，先 `brew install --cask powershell`（需用户确认）。

- [ ] **Step 0.2: 创建功能分支**

```bash
cd /Users/shen/Documents/github.com/EdwardShen125/reverse-skill
git checkout -b feat/windbg-vmware-skills
```

---

## Task 1: 失败的路由测试用例（TDD 红）

**Files:**
- Modify: `skills/tests/routing-benchmark.json`（`cases` 数组末尾追加）

- [ ] **Step 1.1: 追加 10 条用例**

在 JSON 的 `cases` 数组最后一条（`"hint": "case review evidence chain traceability"` 之后）追加：

```json
{ "hint": "windbg kernel debug driver breakpoint", "expect": "R41", "quick": true },
{ "hint": "分析蓝屏 minidump 崩溃转储", "expect": "R41", "quick": false },
{ "hint": "crash dump !analyze cdb triage", "expect": "R41", "quick": true },
{ "hint": "windbg 调试 NDIS 网络栈逆向 驱动", "expect": "R41", "quick": false },
{ "hint": "kernel pwn ret2usr CTF 内核题", "expect": "R17", "quick": true },
{ "hint": "IDA 反编译 so 静态分析", "expect": "R6", "quick": true },
{ "hint": "vmware 靶机 快照 恶意样本分析环境", "expect": "R42", "quick": true },
{ "hint": "vmrun clone 实验环境编排 批量建机", "expect": "R42", "quick": false },
{ "hint": "esxi vsphere 虚拟机环境管理", "expect": "R42", "quick": true },
{ "hint": "恶意样本 沙箱 yara 检测", "expect": "R9", "quick": true }
```

- [ ] **Step 1.2: 验证 JSON 合法**

Run: `python3 -m json.tool skills/tests/routing-benchmark.json > /dev/null && echo VALID`
Expected: `VALID`

- [ ] **Step 1.3: 跑路由测试确认新增 R41/R42 用例失败**

Run: `pwsh -NoProfile -File skills/scripts/test-routing.ps1`
Expected: FAIL（R41/R42 路由不存在，回退 R0；6 条 R41/R42 用例失败，其余 4 条边界用例通过）

- [ ] **Step 1.4: Commit**

```bash
git add skills/tests/routing-benchmark.json
git commit -m "test(routing): add R41/R42 benchmark cases (red)"
```

---

## Task 2: windbg-reverse skill 目录

**Files:**
- Create: `skills/windbg-reverse/SKILL.md`
- Create: `skills/windbg-reverse/references/kd-cheatsheet.md`
- Create: `skills/windbg-reverse/references/crash-dump-workflow.md`
- Create: `skills/windbg-reverse/references/network-stack-debug.md`

- [ ] **Step 2.1: 写 SKILL.md**

```markdown
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
| 靶机 / 快照 / 实验环境 | `vmware-lab/`（组合场景见其 kernel-debug-lab） |

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
□ 前置：靶机已配内核调试串口/KDNET → 见 ../vmware-lab/references/kernel-debug-lab.md
□ 先发现后连接：
  - 管道名：vmware-lab 的 serial_query 读 backingPathName（实测可探测）
  - 波特率：宿主侧探测不到（命名管道无 baud 概念）；权威值用 guest 内
    vmrun_run 跑 `bcdedit /dbgsettings` 读 baudrate，取不到则用惯例 115200
  - 或读 ../vmware-lab/lab-profile.local.md 缓存，跳过发现步骤
□ open_kd_session(connection_string="com:pipe,port=\\.\pipe\com_1,baud=115200", symbols_path=<符号路径>)
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
4. 恢复靶机快照到干净态（vmware-lab）
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
**同级**: `vmware-lab/`（靶机环境）、`malware-analysis/`（样本分诊）

## 任务完成自检

- [ ] 所有 cdb/kd 会话是否已 close？
- [ ] 结论是否标注地址 / 模块 / 具体命令（可复现）？
- [ ] 是否基于 tool-index 确认的 MCP 端点执行？
- [ ] Checklist / journal 回写？
```

- [ ] **Step 2.2: 写 references/kd-cheatsheet.md**

```markdown
# kd / cdb 命令速查（windbg MCP 会话内，经 run_kd_command / run_cdb_command 执行）

## 分诊
| 命令 | 用途 |
|------|------|
| `!analyze -v` | 自动崩溃归因（open_cdb_dump 已自动跑） |
| `.lastevent` | 最后事件 |
| `kb` / `kv` | 栈回溯（带参数/帧指针） |
| `lm` / `lmvm <mod>` | 模块列表 / 模块详情 |
| `~` / `~*s kb` | 线程列表 / 全线程栈 |

## 断点与执行
| 命令 | 用途 |
|------|------|
| `bp <mod>!<func>` | 软件断点 |
| `bu <sym>` | 未解析断点（模块加载后生效） |
| `ba r4 <addr>` | 硬件读断点（4 字节） |
| `g` / `p` / `t` | 继续 / 步过 / 步入 |
| `qd` | 退出（优先用 MCP 的 close_* 释放会话） |

## 内核态
| 命令 | 用途 |
|------|------|
| `!drvobj <DriverName> 2` | 驱动对象与分发表 |
| `!devobj <DeviceName>` | 设备对象 |
| `!devstack <addr>` | 设备栈 |
| `!irp <addr>` | IRP 详情 |
| `!process 0 0` | 进程列表 |
| `.process /i <addr>` | 切换进程上下文（需 g 生效） |

## 内存与搜索
| 命令 | 用途 |
|------|------|
| `db / dd / dps <addr>` | 字节 / 双字 / 符号化转储 |
| `s -a <range> "str"` | ASCII 搜索 |
| `!address <addr>` | 用户态地址区域（cdb） |
| `!pte <addr>` | 页表项（内核） |

## 网络栈
| 命令 | 用途 |
|------|------|
| `!ndiskd.miniport` | 小端口驱动列表 |
| `!ndiskd.filter` | 过滤驱动列表 |
| `!wfpfilters` | WFP 过滤器 |
| `!netstat` | 活动连接（较新 Win10+） |
```

- [ ] **Step 2.3: 写 references/crash-dump-workflow.md**

```markdown
# Crash Dump 分诊工作流

## 1. 发现

- `list_dumps`（默认读注册表 `CrashDump` / `MiniDump` 目录；可传 `directory_path` + `recursive`）
- 区分类型：`.dmp` 完整/内核 dump vs `minidump`（用户态小型转储）

## 2. 打开

`open_cdb_dump(dump_path=..., include_stack_trace=true, include_modules=true, include_threads=false)`

- 返回 `session_id`；初始输出已含 `.lastevent` + `!analyze -v` + kb + lm
- 符号缺失时传 `symbols_path=srv*C:\symbols*https://msdl.microsoft.com/download/symbols`

## 3. 归因检查单

```text
□ BugCheck code 与参数（!analyze 输出）
□ 崩溃时的模块（IMAGE_NAME / MODULE_NAME）是系统还是第三方
□ 栈中最早的第三方帧（STACK_TEXT 逐帧看）
□ SYMBOL_NAME 指向的函数语义
□ 可疑驱动版本 → 联动静态分析（ida-reverse/ghidra-reverse）
```

## 4. 结论输出

- Evidence：session 命令原样输出（可复现 = dump 路径 + 命令序列）
- Finding：崩溃归因 + 置信度（高=第三方帧在栈顶且有符号；中=仅模块归属；低=符号缺失猜测）
- Path：驱动逆向 / 厂商补丁比对（binary-diff）

## 5. 清理

`close_cdb_session(session_id=...)` — MUST 执行
```

- [ ] **Step 2.4: 写 references/network-stack-debug.md**

```markdown
# 内核网络栈逆向方法论（NDIS / WFP / Wsk）

## 定位目标驱动

```text
□ lm 列出可疑 .sys（非微软签名优先）
□ !drvobj <DriverName> 2 → 看 FastIo / DispatchTable 中被接管的网络例程
□ 过滤驱动：!ndiskd.filter；WFP callout：!wfpfilters
```

## 断点策略（按层）

| 层 | 断点 | 观察点 |
|----|------|--------|
| WSK 消费者 | `WskSend` / `WskRecv`（wsk!） | buffer 指针 + 长度，db 转储 |
| NDIS 过滤 | `FilterSendNetBufferLists`（驱动内） | NetBufferList 链，!ndiskd.nbl |
| NDIS 协议 | `NdisSendNetBufferLists` | 同上 |
| WFP callout | `FwpsCalloutRegister` 返回后的 classifyFn | layerId + fixedValues |

## 报文取证

```text
□ 断点命中后：dps 栈回溯确认调用源
□ db <buffer> L<length> 转储原始字节
□ 与抓包（js-reverse / anything-analyzer）对照明文/密文位置
□ 自定义协议结构 → 记录偏移表，交接 ../protocol-reverse/
```

## 加密链路

- 找 `BCryptEncrypt` / `CryptEncrypt` 调用点（用户态样本配合 cdb remote）
- 内核态看 CNG：`bp cng!BCryptEncrypt`，dump 输入输出 buffer 对比

## 收尾

- `close_kd_session` 释放；靶机快照 revert（../vmware-lab/）
```

- [ ] **Step 2.5: Commit**

```bash
git add skills/windbg-reverse/
git commit -m "feat(skill): add windbg-reverse (LAN mcp-windbg kernel/dump/usermode debug)"
```

---

## Task 3: vmware-lab skill 目录 + gitignore

**Files:**
- Create: `skills/vmware-lab/SKILL.md`
- Create: `skills/vmware-lab/references/snapshot-hygiene.md`
- Create: `skills/vmware-lab/references/isolated-network.md`
- Create: `skills/vmware-lab/references/kernel-debug-lab.md`
- Modify: `.gitignore`

- [ ] **Step 3.1: 写 SKILL.md**

```markdown
---
name: vmware-lab
description: Use for VMware lab infrastructure via the LAN vmware-mcp server: target VM environments (snapshot/isolated network hygiene), experiment orchestration (clone/template/batch), and general VM control, including the kernel-debug lab topology bridging to windbg-reverse.
---

# VMware 实验室（靶机 / 编排 / VM 控制）

## ACTION REQUIRED（读完后立刻执行）

1. `NOW`: 读取 `../field-journal/precedent-reverse.md`
2. `NOW`: 确认任务命中三场景之一（靶机环境、实验编排、通用 VM 控制）
3. `NEXT`: 读 `../tool-index.md` 确认 vmware-mcp 能力在线（servicePort 8766）；未注册 → bootstrap 能力名 `vmware-mcp`
4. `ACT`: 先发现后操作（vm_list / network_list 枚举），禁止对未确认的 VM 做破坏性操作（delete/revert）

## 适用场景

- 分析靶机环境：快照纪律、host-only 隔离网、恶意样本投递与恢复
- 实验环境编排：模板部署、克隆（全量/链接）、批量建机、硬件调整
- 通用 VM 控制：电源、guest 文件传输、guest 内执行、截图、键入
- 内核调试实验室（与 `windbg-reverse/` 组合，见 references/kernel-debug-lab.md）

## 三层 API 选层规则（MUST，防乱选）

| 操作类型 | 首选层 | 工具示例 |
|----------|--------|----------|
| guest 内操作（文件/进程/执行） | vmrun 层 | `vmrun_run`, `vmrun_copy_to`, `vmrun_ps` |
| 快照 | vmrun 层 | `vmrun_snapshot_take` / `vmrun_snapshot_revert` |
| VM 生命周期 / 克隆 / 模板 | REST 层 | `vm_create`, `vm_delete`, `template_deploy` |
| 网络拓扑 / 端口转发 | REST 层 | `network_list`, `network_portforward_set` |
| 硬件配置（CPU/内存/网卡/磁盘/串口） | vmcli 层 | `chipset_set_cpu`, `ethernet_set_network`, `serial_query` |

三层功能重叠时按上表选层；首选层工具失败才降级用其他层等价工具，并在 timeline 记录。

## 纪律（MUST）

### 隔离纪律

- 投递恶意样本前 `MUST` 校验无外联：`network_list`（host-only 网段）+ `ethernet_query`（当前网卡绑定）
- 校验不过 → 先改 `ethernet_set_network` 到 host-only，再投递
- 快照 revert 是"清污染"唯一可靠手段

### 快照纪律

- 分析前 `MUST` `vmrun_snapshot_take`（命名含日期与目的）
- 分析后 `MUST` `vmrun_snapshot_revert` 回干净态
- 删除 VM（`vm_delete` / `vmrun_delete`）属破坏性操作，先向用户确认

## 环境值分层（MUST NOT 写死）

- skill 正文只写惯例默认值（管道 `com_1`、波特率 `115200`）
- 单机具体值（VM 名 / 实际管道 / MCP 地址）放 `lab-profile.local.md`（gitignored，格式见 references/kernel-debug-lab.md）
- 优先运行时发现：`vm_list` / `vmrun_list` / `serial_query` / `network_list` 自枚举

## 工作流

### 1. 靶机环境（恶意样本）

```text
□ vm_list / vmrun_list 发现靶机（或读 lab-profile.local.md）
□ vmrun_snapshot_take（干净态基线）
□ 隔离校验（network_list + ethernet_query，不过则改 host-only）
□ vmrun_copy_to 投递样本 → vmrun_run 执行
□ vmrun_screenshot / mks_screenshot 留证
□ 分析交接 malware-analysis（行为）/ windbg-reverse（内核态）
□ vmrun_snapshot_revert 清污染
```

### 2. 实验编排

```text
□ template_create / template_deploy 从模板建机，或 vmrun_clone（链接克隆省磁盘）
□ chipset_set_cpu / chipset_set_memory 调整规格
□ network_portforward_set 配置转发（仅隔离网内）
□ vmrun_list 确认全部就绪
```

### 3. 通用控制

```text
□ 电源：vmrun_start / vmrun_stop / vmrun_suspend
□ 文件：vmrun_copy_to / vmrun_copy_from / vmrun_ls
□ 执行：vmrun_run / vmrun_script / vmrun_ps / vmrun_kill
□ 交互：vmrun_keystrokes / mks_screenshot
```

### 4. 内核调试组合场景（桥接 windbg-reverse）

见 `references/kernel-debug-lab.md` 完整拓扑。

## 建议下一步（选一个编号）

1. 继续当前靶机操作（投递 / 执行 / 取证）
2. 交接 windbg-reverse 连内核调试会话
3. 交接 malware-analysis 做行为分析
4. 导出操作时间线，生成阶段报告（docs-generator）
5. 恢复快照并关闭靶机
6. 暂停，我先确认环境状态

## 语言行为契约

- 内部推理 / 工具选择：English
- 用户可见输出 / 报告 / 菜单：中文（双语标签 中文 / English）

## 参考

- `references/snapshot-hygiene.md`
- `references/isolated-network.md`
- `references/kernel-debug-lab.md`

## 路由上下文

**上游**: MASTER R42
**下游**: `windbg-reverse/`（内核调试）、`malware-analysis/`（样本行为）、`attack-chain/`（实验网络拓扑）
**同级**: `browser-automation/`（自动化面）

## 任务完成自检

- [ ] 破坏性操作（delete/revert）是否经用户确认？
- [ ] 恶意样本投递前是否做了隔离校验？
- [ ] 分析后是否快照 revert 清污染？
- [ ] Checklist / journal 回写？
```

- [ ] **Step 3.2: 写 references/snapshot-hygiene.md**

```markdown
# 快照纪律与污染恢复

## 基线管理

| 时机 | 动作 | 命名约定 |
|------|------|----------|
| 首次装机完成 + 工具就绪 | `vmrun_snapshot_take` | `clean-<日期>-baseline` |
| 每次分析任务开始前 | `vmrun_snapshot_take` | `pre-<case>-<日期>` |
| 分析结束取证完毕 | `vmrun_snapshot_revert` | 回 `pre-*` 或 `clean-*` |
| 系统更新 / 工具升级后 | 重新拍 baseline | `clean-<新日期>-baseline` |

## 操作顺序（不可颠倒）

```text
1. vmrun_snapshot_take      ← 必须在投递样本之前
2. 投递 + 分析
3. 取证导出（vmrun_copy_from / mks_screenshot）
4. vmrun_snapshot_revert    ← 清污染
5. vmrun_tools_state 确认 Tools 正常（revert 后偶发失效）
```

## 注意

- 链接克隆的 VM：快照 revert 影响该 VM 自身链，不影响基准模板
- `snapshot_delete` 删除的是快照节点不是 VM；删错节点会丢失回退点 → 删除前 `snapshot_list` 树确认
- revert 后 guest IP 可能变化（DHCP）：用 `vmrun_guest_ip` 重新确认再连调试器
```

- [ ] **Step 3.3: 写 references/isolated-network.md**

```markdown
# host-only 隔离网与端口转发

## 网络发现

```text
□ network_list → 列主机虚拟网络（找 host-only 段，如 VMnet1: 192.168.x.0/24）
□ ethernet_query（vmcli 层）→ 查靶机当前网卡绑定的网络名
□ vm_nic_list（REST 层）→ 同一信息的 REST 视图
```

## 隔离判定标准

满足全部三条才算"无外联"：

1. 网卡绑定网络是 host-only（无 NAT / 桥接）
2. host-only 网段内无网关指向外网的代理配置
3. （可选）`vmrun_ps` 查 guest 内无外联路由（`route print` 默认路由仅指向 host-only 网卡）

## 改造

```text
□ ethernet_set_network → 绑定到 host-only 网络
□ ethernet_set_connected=true → 确保启动即连
□ 需要定向放行时：network_portforward_set 只转发分析机所需的端口
```

## 端口转发（仅隔离网内）

| 用途 | 转发 | 说明 |
|------|------|------|
| cdb 远程调试 | host:5005 → guest:5005 | 配 windbg-reverse open_cdb_remote |
| KDNET 内核调试 | host:50000 → guest:50000 | 配 open_kd_session net: 连接串 |

转发规则用完删除（`network_portforward_delete`），避免残留暴露面。
```

- [ ] **Step 3.4: 写 references/kernel-debug-lab.md**

```markdown
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
```

- [ ] **Step 3.5: .gitignore 加条目**

在 `.gitignore` 的 `# 工具索引（每台机器不同）` 注释块之后追加：

```gitignore
# 实验室本地环境值（每台机器不同）
skills/vmware-lab/lab-profile.local.md
```

- [ ] **Step 3.6: Commit**

```bash
git add skills/vmware-lab/ .gitignore
git commit -m "feat(skill): add vmware-lab (LAN vmware-mcp target/env/control + kernel-debug lab)"
```

---

## Task 4: 路由实现（TDD 绿）

**Files:**
- Modify: `skills/config/routing.json`
- Modify: `skills/MASTER-ROUTING.md`
- Modify: `skills/routing.md`
- Modify: `skills/SKILL.md`

- [ ] **Step 4.1: routing.json 加两条路由**

在 `"routes"` 对象内、`"R40"` 条目之后追加（注意保持 2 空格缩进风格）：

```json
    "R41": {
      "label": "WinDbg debug / kernel / dump",
      "skill": "windbg-reverse/SKILL.md",
      "keywords": [
        { "must": "windbg|\\bkd\\b|\\bcdb\\b|crash.?dump|minidump|dump.?分析|蓝屏|bsod|内核.?调试|驱动.?逆向|driver.?reverse|!analyze|ndiskd", "note": "WinDbg/kd/cdb 内核与 dump 调试；kernel pwn CTF 语境仍归 R17" }
      ]
    },
    "R42": {
      "label": "VMware lab infrastructure",
      "skill": "vmware-lab/SKILL.md",
      "keywords": [
        { "must": "vmware|vsphere|esxi|\\bvmrun\\b|靶机|虚拟机.?环境|host.?only|vm.?编排|实验环境", "note": "VMware 产品名/靶机/实验编排" },
        { "must": "快照|snapshot", "mustAll": ["靶机|虚拟机|vmware|vsphere|esxi|vmrun|实验|恶意|样本"], "note": "快照需语境限定（mustAll）：与 R9 恶意样本语境叠加时（如『vmware 靶机 快照 恶意样本』）R42 命中 2 规则以 2:1 压过 R9 单规则；裸『快照』（如『Frida hook 快照逻辑』）不命中 R42" }
      ]
    }
```

- [ ] **Step 4.2: priority 数组追加**

把 `priority` 数组末尾的 `"R39", "R0"` 改为 `"R39", "R41", "R42", "R0"`（即 R41/R42 插在 R0 之前）。

- [ ] **Step 4.3: MASTER-ROUTING.md 加行**

在优先级表中 `| **R0** | 通用逆向...` 这一行**之前**插入两行：

```markdown
| **R41** | WinDbg / kd / cdb / 蓝屏 / dump | `windbg-reverse/` |
| **R42** | VMware / 靶机 / 快照 / 实验环境 | `vmware-lab/` |
```

注意：`verify-routing-coherence.ps1` 校验此表与 priority 数组一致，行序必须与数组一致（R41、R42 在 R0 前）。

- [ ] **Step 4.4: routing.md 三轴表加行**

读 `skills/routing.md`，在"按目标类型"、"按用户意图"、"按工具链"三张表中分别追加：

按目标类型：
```markdown
| Windows 内核/驱动/crash dump | `windbg-reverse/` — WinDbg MCP 调试 | `ida-reverse/` — 静态 |
| 靶机/虚拟机实验环境 | `vmware-lab/` — VMware MCP 编排 | — |
```

按用户意图：
```markdown
| "调试这个蓝屏 dump" / "内核断点跟一下这个驱动" | `windbg-reverse/` |
| "给我快照一台靶机投样本" / "编排一个实验网络" | `vmware-lab/` |
```

按工具链：
```markdown
| WinDbg / kd / cdb | `windbg-reverse/` |
| vmrun / vsphere / esxi | `vmware-lab/` |
```

（实际行格式以该文件现有表为准，保持列数一致。）

- [ ] **Step 4.5: 根 SKILL.md 模块表加 2 行**

在 `skills/SKILL.md` 的"当前模块"表中 `| **RF / SDR** | ...` 行后追加：

```markdown
| **WinDbg 调试** | `windbg-reverse/` | 内核/驱动调试、crash dump 分诊、用户态远程调试、NDIS/WFP 网络栈逆向（LAN mcp-windbg） |
| **VMware 实验室** | `vmware-lab/` | 靶机环境、快照/隔离纪律、实验编排、通用 VM 控制（LAN vmware-mcp）；含内核调试实验室组合场景 |
```

- [ ] **Step 4.6: 跑路由测试确认转绿**

Run: `pwsh -NoProfile -File skills/scripts/test-routing.ps1`
Expected: PASS（166+10=176 用例全过，含 Task 1 的 6 条 R41/R42 用例与 4 条边界用例）

- [ ] **Step 4.7: 跑 coherence 校验**

Run: `pwsh -NoProfile -File skills/scripts/verify-routing-coherence.ps1`
Expected: 全部 OK（priority 数组与 MASTER-ROUTING 表一致、R41/R42 的 skill 文件存在）

- [ ] **Step 4.8: Commit**

```bash
git add skills/config/routing.json skills/MASTER-ROUTING.md skills/routing.md skills/SKILL.md
git commit -m "feat(routing): add R41 windbg-reverse / R42 vmware-lab routes (green)"
```

---

## Task 5: manifest 登记 + 能力清单三处同步

**Files:**
- Modify: `skills/scripts/bootstrap-manifest.json`
- Modify: `kali/scripts/bootstrap-manifest.json`
- Modify: `skills/scripts/refresh-tool-index.ps1`
- Modify: `RULES.md`
- Modify: `RULES_zh.md`

> ⚠️ `verify-doc-facts.ps1` 强校验 RULES.md / RULES_zh.md / skills/SKILL.md 三处能力清单与 `skills/scripts/bootstrap-manifest.json` **完全一致（数量+成员）**，漏一处即 CI FAIL。

- [ ] **Step 5.1: skills/scripts/bootstrap-manifest.json 加 2 条**

在 `capabilities` 数组末尾追加：

```json
    {
      "name": "windbg-mcp",
      "bootstrapKind": "local-http-mcp",
      "mcpNames": ["windbg"],
      "mcpUrl": "http://192.168.100.175:8765/mcp/",
      "servicePort": 8765,
      "canAutoInstall": false,
      "verificationMode": "service-or-registration",
      "manualInstallHint": "内网 MCP：确保 192.168.100.175:8765 可达（kd.exe 运行于该 lab-host）；bootstrap 仅注册 URL 与端口探测，不安装服务"
    },
    {
      "name": "vmware-mcp",
      "bootstrapKind": "local-http-mcp",
      "mcpNames": ["vmware"],
      "mcpUrl": "http://192.168.100.175:8766/mcp/",
      "servicePort": 8766,
      "canAutoInstall": false,
      "verificationMode": "service-or-registration",
      "manualInstallHint": "内网 MCP：确保 192.168.100.175:8766 可达（vmware-mcp 运行于该 lab-host）；bootstrap 仅注册 URL 与端口探测，不安装服务"
    }
```

- [ ] **Step 5.2: kali/scripts/bootstrap-manifest.json 加同样 2 条**

在 kali 的 `capabilities` 数组末尾追加：

```json
    {
      "name": "windbg-mcp",
      "bootstrapKind": "local-http-mcp",
      "mcpNames": ["windbg"],
      "mcpUrl": "http://192.168.100.175:8765/mcp/",
      "servicePort": 8765,
      "canAutoInstall": false,
      "verificationMode": "service-or-registration",
      "manualInstallHint": "内网 MCP：确保 192.168.100.175:8765 可达（kd.exe 运行于该 lab-host）；bootstrap 仅注册 URL 与端口探测，不安装服务"
    },
    {
      "name": "vmware-mcp",
      "bootstrapKind": "local-http-mcp",
      "mcpNames": ["vmware"],
      "mcpUrl": "http://192.168.100.175:8766/mcp/",
      "servicePort": 8766,
      "canAutoInstall": false,
      "verificationMode": "service-or-registration",
      "manualInstallHint": "内网 MCP：确保 192.168.100.175:8766 可达（vmware-mcp 运行于该 lab-host）；bootstrap 仅注册 URL 与端口探测，不安装服务"
    }
```

- [ ] **Step 5.3: refresh-tool-index.ps1 两处更新**

1. `$scriptRefs` 哈希表（`'bkcrack' = ...` 行后）追加：

```powershell
    'windbg-mcp' = @('windbg-reverse/SKILL.md')
    'vmware-mcp' = @('vmware-lab/SKILL.md')
```

2. `$capabilityNames` 数组（第 103 行附近）末尾 `'bkcrack'` 后追加 `', 'windbg-mcp', 'vmware-mcp'`：

```powershell
$capabilityNames = @('jadx', 'apktool', 'jeb-pro', 'frida', 'frida-ps', 'idalib-mcp', 'jshookmcp', 'reqable-mcp', 'anything-analyzer', 'idapro', 'r2', 'rabin2', 'adb', 'agent-browser', 'ghidra-mcp', 'seclists', 'proxycat', 'burpsuite-mcp', 'pentestswarm', 'nmap', 'binwalk', 'yara', 'pwntools', 'bkcrack', 'windbg-mcp', 'vmware-mcp')
```

- [ ] **Step 5.4: RULES.md 能力清单追加**

找到 `Supported capability names (must match ...)` 一行，在 `bkcrack` 之后追加 `、windbg-mcp、vmware-mcp`（保持原有顿号分隔风格）。

- [ ] **Step 5.5: RULES_zh.md 能力清单追加**

找到 `支持的能力名` 一行，同样在 `bkcrack` 后追加 `、windbg-mcp、vmware-mcp`。

- [ ] **Step 5.6: skills/SKILL.md 能力清单追加**

找到 `支持的能力（以 ... bootstrap-manifest.json 为准）：jadx、...、bkcrack` 一行，末尾追加 `、windbg-mcp、vmware-mcp`。

- [ ] **Step 5.7: RULES.md 触发关键词追加**

在 RULES.md 的 Trigger Keywords 列表中（`- symbol migration, 符号迁移...` 行附近）追加：

```markdown
- WinDbg, kernel debug, 内核调试, crash dump, minidump, 蓝屏, BSOD, driver reverse, 驱动逆向, dump 分析
- VMware, vSphere, ESXi, vmrun, snapshot, 快照, 靶机, target VM, 虚拟机实验环境, host-only, 实验编排
```

- [ ] **Step 5.8: RULES_zh.md 触发关键词追加**

在 RULES_zh.md 对应触发关键词列表中追加同样两组（中英双语与该文件现有风格一致）。

- [ ] **Step 5.9: 校验脚本全过**

```bash
python3 -m json.tool skills/scripts/bootstrap-manifest.json > /dev/null && echo VALID1
python3 -m json.tool kali/scripts/bootstrap-manifest.json > /dev/null && echo VALID2
pwsh -NoProfile -File skills/scripts/verify-doc-facts.ps1
pwsh -NoProfile -File skills/scripts/test-bootstrap-supply-chain.ps1
```

Expected: VALID1 / VALID2；两个脚本全部 OK。若 supply-chain 测试报 manifest 字段缺失（如必填 `docsUrl`），按报错补字段后重跑。

- [ ] **Step 5.10: Commit**

```bash
git add skills/scripts/bootstrap-manifest.json kali/scripts/bootstrap-manifest.json skills/scripts/refresh-tool-index.ps1 RULES.md RULES_zh.md skills/SKILL.md
git commit -m "feat(bootstrap): register windbg-mcp/vmware-mcp LAN capabilities + sync doc fact tables"
```

---

## Task 6: INDEX.md 重新生成

**Files:**
- Modify: `skills/INDEX.md`（由脚本生成）

- [ ] **Step 6.1: 重新生成索引**

Run: `pwsh -NoProfile -File skills/scripts/extract-summaries.ps1`
Expected: 无报错；`skills/INDEX.md`（或脚本实际输出路径）中出现 windbg-reverse 与 vmware-lab 两行。

- [ ] **Step 6.2: 校验新鲜度**

Run: `pwsh -NoProfile -File skills/scripts/extract-summaries.ps1 -Check`
Expected: OK（无 drift）

- [ ] **Step 6.3: Commit**

```bash
git add skills/INDEX.md
git commit -m "chore(index): regenerate skill INDEX for windbg-reverse/vmware-lab"
```

---

## Task 7: 端到端验证 + 本机接入

- [ ] **Step 7.1: 全量校验套件**

```bash
pwsh -NoProfile -File skills/scripts/smoke.ps1
pwsh -NoProfile -File skills/scripts/test-routing.ps1
pwsh -NoProfile -File skills/scripts/verify-routing-coherence.ps1
pwsh -NoProfile -File skills/scripts/verify-doc-facts.ps1
pwsh -NoProfile -File skills/scripts/test-bootstrap-supply-chain.ps1
```

Expected: 全部通过。

- [ ] **Step 7.2: Bash 侧平价验证**

```bash
bash -n skills/scripts/refresh-tool-index.sh && echo SYNTAX-OK
bash skills/scripts/refresh-tool-index.sh
grep -c "windbg-mcp\|vmware-mcp" skills/tool-index.md
```

Expected: SYNTAX-OK；tool-index.md 中两个能力各出现 ≥1 次（capability 视图含注册/端口状态）。确认后 `git checkout -- skills/tool-index.md 2>/dev/null; rm -f skills/tool-index.json`（本机生成物不入库，已 gitignored，无需清理 git，仅确认生成即可）。

- [ ] **Step 7.3: MCP 实际可达复测**

```bash
curl -s -X POST http://192.168.100.175:8765/mcp/ -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"1.0"}}}' --max-time 10 | head -c 200
curl -s -X POST http://192.168.100.175:8766/mcp/ -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"1.0"}}}' --max-time 10 | head -c 200
```

Expected: 两处均返回 `serverInfo`（mcp-windbg / vmware-mcp v1.29.0）。

- [ ] **Step 7.4: 本机客户端注册（用户机器）**

把以下写入 `~/.claude/mcp.json` 的 `mcpServers`（或让 bootstrap 自动写）：

```json
"windbg": { "url": "http://192.168.100.175:8765/mcp/" },
"vmware": { "url": "http://192.168.100.175:8766/mcp/" }
```

- [ ] **Step 7.5: 最终提交（如有遗留改动）**

```bash
git status
git add -A ':!skills/tool-index.md' ':!skills/tool-index.json' ':!skills/vmware-lab/lab-profile.local.md'
git commit -m "chore: final verification pass for windbg/vmware skills" || echo "nothing to commit"
```

---

## 完成标准（对照 spec 第 7 节）

- [ ] routing-benchmark 176 用例全过
- [ ] verify-routing-coherence / verify-doc-facts / test-bootstrap-supply-chain / smoke 全过
- [ ] INDEX.md 含两个新 skill
- [ ] refresh-tool-index 后 capability 视图含 windbg-mcp / vmware-mcp
- [ ] 本机 `~/.claude/mcp.json` 已注册两个内网 MCP
