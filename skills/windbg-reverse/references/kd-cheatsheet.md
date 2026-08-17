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
