# iOS 15.0 看门狗与自旋锁修复开发日记

**日期：** 2026-08-16
**维护分支：** `2.x`
**基线提交：** `44d398aea2a2ea2c6dbece1c0db84ddd5f70388b`

## 问题范围

本次调查覆盖 iPhone11,6（A12、arm64e）、iOS 15.0（19A346）提交的两份 panic 报告。两次 panic 分别发生在应用进程 `Reynard` 和 `launchd`（pid 1）中。前者的错误文本是 `Spinlock ... timeout`，后者是 `initproc exited`；两者均是内核 panic，而不是普通的应用看门狗终止。

| 报告 | 时间 | 直接错误 | 受影响进程 | 调查结论 |
| --- | --- | --- | --- | --- |
| `panic-full-2026-08-16-182803.000.ips` | 18:28:03 | `Spinlock ... timeout` | `Reynard` | 与 iOS 15 arm64e 的 dyld 共享缓存处理风险一致。 |
| `panic-full-2026-08-16-183218.000.ips` | 18:32:18 | `initproc exited`，namespace 2 / subcode `0xa` | `launchd`（pid 1） | 表明关键初始化进程退出；必须避免 launchd 内部的未检查错误路径。 |

> 现有设置界面已经明确提示：在 iOS 15 arm64e 上启用自旋锁修复时，黑名单应用及其扩展存在 spinlock panic 风险。此次补丁将安装/更新期间的短生命周期预热进程从该高风险注入路径中隔离。

`installd` 的 Logos hook 在当前代码中处于注释状态，因此它不是这次问题的实际执行路径。处理重点转向 launchd 的进程启动分派、dyld 共享缓存注入和看门狗的安全模式标记路径。

## 实施的修复

| 文件 | 修改 | 目的 |
| --- | --- | --- |
| `BaseBin/launchdhook/src/roothider.m` | 对 iOS 15 arm64e、可移除应用容器且带有 `ActivePrewarm` 或 `DYLD_USE_CLOSURES` 的启动，直接使用原始 spawn。 | 避免应用安装或更新后预热临时进程时进入 dyld 注入与共享缓存的竞争窗口；正常前台启动仍走原有路径。 |
| `BaseBin/launchdhook/src/jbserver/jbdomain_watchdog.c` | 检查安全模式标记文件的 `fopen` 和 `fclose` 结果。 | 防止在 launchd 中对空 `FILE *` 调用 `fclose`，将标记写入失败安全地返回给原始看门狗流程，而非终止 pid 1。 |
| `BaseBin/watchdoghook/src/main.m` | 校验看门狗负载存在且以 NUL 结束；服务端拦截失败时转交原始 IOKit 调用。 | 不将非字符串或无法持久化的负载当作可恢复的用户空间 panic，避免错误的用户空间重启链。 |
| `ci/verify-ipa.sh` | 新增归档结构、`Info.plist` 与上述三处防护的回归检查。 | 对每个在线构建产物建立可重复的最低验证基线。 |
| `.github/workflows/roothide.yml` | 重建为带缓存、验证、产物保留和受控发布的流水线。 | 缩短重复构建时间，避免从上游克隆覆盖当前修复，并只发布已验证的产物。 |

## 验证边界

已完成的自动验证包括 shell 语法、工作流关键步骤、补丁定位回归检查、IPA archive/metadata 验证，以及 Git 差异空白检查。由于 iOS 15.0 arm64e 内核自旋锁属于运行时内核交互问题，不能仅靠 macOS 编译完全证明消除；仍需要在目标设备上执行安装、覆盖更新、预热、前后台切换和重复重启测试。

建议的设备验收条件如下。

| 场景 | 通过标准 |
| --- | --- |
| 新安装第三方应用 | 无系统重启、无安全模式、无新的 `Spinlock ... timeout` panic。 |
| 覆盖更新同一应用 | 安装完成且可正常首次启动；不产生 `initproc exited` panic。 |
| 有扩展的应用更新 | 应用与扩展均能在后续前台启动中运行；预热阶段不注入。 |
| 看门狗触发路径 | 可持久化的用户空间 panic 建立安全模式标记；不可持久化或无效负载回落至系统原始处理。 |

## 构建、验证与发布

线上流程在 macOS 14 runner 上执行，完整签出当前分支和子模块，缓存 Theos、SDK 与已编译的 trustcache。构建后的 `.tipa` 先经 `ci/verify-ipa.sh` 验证，随后上传为 30 天可下载的构建产物。只有推送 `v*` 标签或手动明确请求发布并提供标签时，才会创建 GitHub Release；发布 job 仅下载构建 job 已验证的 artifact。

## 参考资料

[1] [项目当前 2.x 分支与构建说明](https://github.com/qwer12345uui/Dopamine2-roothide)
[2] [上游 iOS 15 自旋锁相关公开问题](https://github.com/roothide/Dopamine2-roothide/issues/101)
[3] [iPhone 上 `initproc exited` panic 的相似案例](https://github.com/frida/frida/issues/1380)
