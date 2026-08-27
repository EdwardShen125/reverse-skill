---
name: pve-lab
description: Use for Proxmox VE lab infrastructure via the LAN pve-mcp server: target VM environments (snapshot/isolated network hygiene), experiment orchestration (clone/template/batch), and general VM control, including the kernel-debug lab topology bridging to windbg-reverse.
---

# Proxmox VE 实验室（靶机 / 编排 / VM 控制）

## ACTION REQUIRED（读完后立刻执行）

1. `NOW`: 读取 `../field-journal/precedent-reverse.md`
2. `NOW`: 确认任务命中三场景之一（靶机环境、实验编排、通用 VM 控制）
3. `NEXT`: 读 `../tool-index.md` 确认 pve-mcp 能力在线（servicePort 8767）；未注册 → bootstrap 能力名 `pve-mcp`
4. `ACT`: 先发现后操作（vm_list / network_list 枚举），禁止对未确认的 VM 做破坏性操作（delete/revert）

## 适用场景

- 分析靶机环境：快照纪律、隔离网隔离、恶意样本投递与恢复
- 实验环境编排：模板部署、克隆（全量/链接）、批量建机、硬件调整
- 通用 VM 控制：电源、guest 文件传输、guest 内执行、截图、键入
- 内核调试实验室（与 `windbg-reverse/` 组合，见 references/kernel-debug-lab.md）

## PVE API 层级（不同于 VMware 三层）

| 操作类型 | API 层 | 工具示例 |
|----------|--------|----------|
| VM 生命周期 / 克隆 / 模板 | REST API | `vm_create`, `vm_delete`, `vm_clone`, `template_deploy` |
| 快照管理 | REST API | `snapshot_create`, `snapshot_delete`, `snapshot_list`, `snapshot_revert` |
| 电源控制 | REST API | `vm_start`, `vm_stop`, `vm_shutdown`, `vm_suspend`, `vm_resume` |
| 网络配置 | REST API | `network_list`, `vm_network_list`, `network_update` |
| 硬件配置（CPU/内存/磁盘/串口） | REST API | `vm_config_set`, `vm_config_get` |
| Guest 内操作 | QEMU Agent | `guest_exec`, `guest_file_read`, `guest_file_write` (需 guest-agent 运行) |

PVE 使用统一的 REST API，通过 vm_id（数字，如 300）标识 VM。串口配置通过 VM config 修改。

## 纪律（MUST）

### 隔离纪律

- 投递恶意样本前 `MUST` 校验无外联：`network_list`（确认 VM 处于隔离网络）+ `vm_network_get`（检查网卡绑定）
- 校验不过 → 先改 `vm_network_update` 到隔离网桥，再投递
- 快照 revert 是"清污染"唯一可靠手段

### 快照纪律

- 分析前 `MUST` `snapshot_create`（命名含日期与目的，如 `pre-analysis-20260827`）
- 分析后 `MUST` `snapshot_revert` 回干净态
- 删除 VM（`vm_delete`）属破坏性操作，先向用户确认

### PVE 特殊注意事项

- **VM ID 基准**: PVE 用数字 ID（如 300）而非名称，所有操作以此为准
- **串口配置**: 内核调试需在 VM config 中配置 `serial0: socket`，`serial1: socket` (可选用于 display)
- **QEMU Agent**: Guest 内操作需要 `guest-agent` 运行，安装 `qemu-guest-agent` 并启用

## 环境值分层（MUST NOT 写死）

- skill 正文只写惯例默认值（VM ID 300、串口 socket、波特率 115200）
- 单机具体值（VM ID / 实际串口 socket / MCP 地址）放 `lab-profile.local.md`（gitignored，格式见 references/kernel-debug-lab.md）
- 优先运行时发现：`vm_list` / `vm_config_get` / `network_list` 自枚举

## 工作流

### 1. 靶机环境（恶意样本）

```text
□ vm_list 发现靶机（或读 lab-profile.local.md 获取 VM ID）
□ snapshot_create（干净态基线）
□ 隔离校验（network_list + vm_network_get，不过则改隔离网桥）
□ guest_file_write 投递样本 → guest_exec 执行（需 guest-agent）
□ 截图留证（vm_console_snapshot）
□ 分析交接 malware-analysis（行为）/ windbg-reverse（内核态）
□ snapshot_revert 清污染
```

### 2. 实验编排

```text
□ vm_clone 从模板克隆（full=1 全量，full=0 链接）
□ vm_config_set 调整规格（cores/memory/cpu_type）
□ network_update 配置网络桥接
□ vm_list 确认全部就绪
```

### 3. 通用控制

```text
□ 电源：vm_start / vm_stop / vm_shutdown / vm_suspend
□ 文件：guest_file_write / guest_file_read / guest_exec（需 guest-agent）
□ 配置：vm_config_set / vm_config_get
□ 监控：vm_status / vm_rrd（资源使用图表）
```

### 4. 内核调试组合场景（桥接 windbg-reverse）

见 `references/kernel-debug-lab.md` 完整拓扑。**生产环境强制预检**：
```bash
# 调试前必须执行依赖检查
bash skills/pve-lab/scripts/check-dependencies.sh <vmid>

# 调试结束后必须执行会话清理
bash skills/pve-lab/scripts/cleanup-session.sh <vmid>

# 紧急情况使用重置脚本
bash skills/pve-lab/scripts/emergency-reset.sh <vmid>
```

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

- `references/kernel-debug-lab.md` - 内核调试实验室拓扑与标准流程
- `references/troubleshooting-guide.md` - **系统化故障排除流程**（快速诊断、症状索引、应急处理）
- `references/snapshot-hygiene.md`
- `references/isolated-network.md`
- `scripts/check-dependencies.sh` - **生产环境依赖检查脚本**（MCP/VM/串口/管道/快照/网络）
- `scripts/cleanup-session.sh` - **会话资源清理脚本**（防止泄漏）
- `scripts/emergency-reset.sh` - **紧急重置脚本**（其他方法失败时）

## 路由上下文

**上游**: MASTER R43
**下游**: `windbg-reverse/`（内核调试）、`malware-analysis/`（样本行为）、`attack-chain/`（实验网络拓扑）
**同级**: `browser-automation/`（自动化面）

## 任务完成自检

- [ ] 破坏性操作（delete/revert）是否经用户确认？
- [ ] 恶意样本投递前是否做了隔离校验？
- [ ] 分析后是否快照 revert 清污染？
- [ ] Checklist / journal 回写？
