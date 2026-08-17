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
