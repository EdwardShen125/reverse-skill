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
