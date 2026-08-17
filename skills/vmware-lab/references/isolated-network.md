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
