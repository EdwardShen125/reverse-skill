# 快照纪律与污染恢复

## 基线管理

| 时机 | 动作 | 命名约定 |
|------|------|----------|
| 首次装机完成 + 工具就绪 | `snapshot_create` | `clean-<日期>-baseline` |
| 每次分析任务开始前 | `snapshot_create` | `pre-<case>-<日期>` |
| 分析结束取证完毕 | `snapshot_revert` | 回 `pre-*` 或 `clean-*` |
| 系统更新 / 工具升级后 | 重新拍 baseline | `clean-<新日期>-baseline` |

## 操作顺序（不可颠倒）

```text
1. snapshot_create(vmid, name="pre-<case>-<date>")  ← 必须在投递样本之前
2. 投递 + 分析
3. 取证导出（guest_file_read / vm_console_snapshot）
4. snapshot_revert(vmid, snapname="pre-<case>-<date>")  ← 清污染
5. vm_status 确认 VM 状态正常
```

## 注意

- PVE 快照包含磁盘状态和部分配置，不包含内存（除非使用带内存的 snapshot）
- `snapshot_delete` 删除的是快照节点不是 VM；删错节点会丢失回退点 → 删除前 `snapshot_list` 确认
- revert 后 guest IP 可能变化（DHCP）：用 `guest_network_get`（需 guest-agent）或 vm_config_get 重新确认再连调试器
- 带 RAM 的快照（`vmstate=1`）更大但恢复更快，仅必要时使用
