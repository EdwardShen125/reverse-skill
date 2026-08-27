# 隔离网与端口转发

## 网络发现

```text
□ network_list（cluster/network）         → 列集群网络桥接（找隔离桥，如 vmbr0）
□ vm_network_get(vmid)                   → 查靶机当前网卡绑定的网络桥
□ vm_config_get(vmid, "net0")           → 查网卡配置详情（bridge/model）
```

## 隔离判定标准

满足全部三条才算"无外联"：

1. 网卡绑定网络桥是隔离桥（无 NAT / 上游路由）
2. 隔离桥无网关指向外网
3. （可选）`guest_exec` 查 guest 内无外联路由（`ip route` 默认路由仅指向隔离网桥）

## 改造

```text
□ vm_network_update(vmid, net="net0", bridge="vmbr0")  → 绑定到隔离桥
□ firewall_set(vmid, policy="drop")                   → 默认丢弃策略
□ 需要定向放行时：firewall_rule_add 仅放行分析机 IP
```

## 端口转发（仅隔离网内）

PVE 端口转发通过防火墙规则或宿主机 iptables 实现：

| 用途 | 转发 | 说明 |
|------|------|------|
| cdb 远程调试 | host:5005 → guest:5005 | 配 windbg-reverse open_cdb_remote |
| KDNET 内核调试 | host:50000 → guest:50000 | 配 open_kd_session net: 连接串 |

通过 `firewall_rule_add(vmid, ...)` 配置 DNAT 规则。规则用完删除（`firewall_rule_delete`），避免残留暴露面。

## 防火墙规则示例

```text
# 放行分析机访问靶机端口
firewall_rule_add(vmid=300, action="ACCEPT", source="192.168.1.100", dport="5005", proto="tcp")

# 阻断外联
firewall_set(vmid=300, policy="DROP", direction="out")
```
