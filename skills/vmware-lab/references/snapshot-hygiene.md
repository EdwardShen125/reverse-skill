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
