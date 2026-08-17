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
