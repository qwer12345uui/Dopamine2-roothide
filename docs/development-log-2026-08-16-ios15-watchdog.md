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

## 追加调查：安装或更新后的安全模式问题

新增证据包括一段现场视频、三个系统会话记录，以及两个应用的 `bug_type 309` 崩溃报告。视频显示在安装 `LocalIocRecorder 1.0.2` 后发生长时间 respring 卡死，随后出现 Dopamine 的 `Watchdog Timeout` 提示并自动禁用注入。该提示说明安全模式是**保护动作的结果**，而不是对“插件已经被禁用”的反证；禁用发生在看门狗检测到关键进程迟迟未恢复之后。

与此同时，新增 IPS 还包含必须与看门狗问题分离处理的应用兼容性失败：`com.fenghuang.7703` 在启动后不到 20 毫秒由 dyld 以 `Foundation.URLRequest.httpMethod` 符号缺失终止。这是应用二进制请求了 iOS 15.0 的 Foundation 中没有的符号，无法由越狱注入或看门狗修复使其在该系统版本上运行。两份支付宝报告均是应用自身调用 `abort()` 的 `SIGABRT`，没有将 Roothide 动态库列为崩溃镜像或给出看门狗超时作为终止原因。因此，修复目标保持为**避免安装事务和首次可移除应用启动使关键系统进程卡死**，而不掩盖单个应用的最低系统版本或自身中止。

| 新证据 | 观察结果 | 修复处理 |
| --- | --- | --- |
| `IMG_0546.mov` | 安装后 respring 长时间无响应，最终由 Dopamine 保护性安全模式恢复。 | 保留看门狗保护；从源头减少安装服务继承注入与暂停子进程的概率。 |
| `lAGbxgJBvYTq` IPS | `DYLD 4 Symbol missing`，`URLRequest.httpMethod` 在 iOS 15.0 Foundation 中缺失。 | 记录为应用/系统版本兼容性失败，不通过越狱层伪造缺失 API。 |
| `AlipayWallet` IPS | `SIGABRT`，应用内多线程运行后中止；无 Roothide 注入镜像证据。 | 记录为独立应用中止，避免与安装服务看门狗问题混淆。 |
| 上游安装问题 #113 | 上游维护者的首要隔离建议是关闭注入并 userspace reboot；用户随后确认安装恢复。 | 本补丁在安装服务进程层面默认执行该隔离，而不要求关闭整个越狱环境。 [4] |

本轮代码修改如下。

| 文件 | 修改 | 安全性意义 |
| --- | --- | --- |
| `BaseBin/launchdhook/src/roothider.m` | 将首次可移除应用启动触发的 `fix__iosConnect` 从多个 `assert` 改为检查失败即记录并返回；仅在新连接成功后替换旧连接。 | 该逻辑运行在 `launchd`，因此任一 IOSurface 符号、服务或连接的暂时不可用都不得终止 pid 1 并升级为看门狗恢复。 |
| `BaseBin/systemhook/src/common.c` | 将 `installd`、`appstored`、`storekitd` 与 `mobile_installation_proxy` 加入共享 spawn 注入黑名单。 | 这些已受平台信任的安装服务不会再继承 systemhook 动态库、子进程暂停及 dyld patch 处理；普通应用的后续正常启动不受此黑名单影响。 |
| `ci/verify-ipa.sh` | 新增对 IOSurface 非致命分支和安装服务隔离规则的回归检查。 | 每次在线构建均验证本轮防护仍在 IPA 所属源码中。 |

追加的设备验收应严格分开观察安装服务和应用兼容性：对可在 iOS 15.0 正常运行的 App Store 应用连续执行新安装、覆盖更新、重启 SpringBoard 与首次前台启动，预期不再出现 Dopamine 安全模式提示。若某个应用仍报告 `DYLD Symbol missing`，应将其判定为该应用不支持 iOS 15.0，而非运行本补丁后的安装服务回归。

[4] [上游 App Store 安装和更新失败问题 #113](https://github.com/roothide/Dopamine2-roothide/issues/113)

## 追加调查二：安装完成后的长时间卡死与 Boot Logo

本轮重新检查视频后，时间线比此前的“安装期预热”更明确：安装操作在约 `00:08` 结束，约 `01:15` 才进入黑屏旋转状态，旋转持续到约 `03:15`，随后经历启动画面并在约 `03:59` 出现 `Watchdog Timeout`。这说明问题不是安装命令立即失败，而是**安装完成后 LaunchServices 数据库重建与 SpringBoard 恢复阶段发生的 userspace 重启卡死**。视频中约两分钟的可见旋转时间，与用户报告的较长等待并不矛盾；看门狗记录的是关键进程未恢复后的保护性降级。

当前分支已确认以 RootHide 上游 `2.4.9.25` 对应的 `44d398a` 为祖先，故不存在可直接合并的更新提交；在该最新基线上保留先前的安装服务隔离修复，并针对最新版本新增的 `lsd` 逻辑实施补强。[5]

| 触发链路 | 代码证据 | 修复 |
| --- | --- | --- |
| 应用数据库重建 | `new_LSServer_RebuildApplicationDatabases` 在原实现中每次回调均异步执行 `uicache -a`，并等待其退出。`uicache -a` 又会触发 LaunchServices 重建。 | 为 iOS 15 arm64e 将该自动全量刷新改为默认关闭；只有显式创建 `jbroot:/.enable_auto_uicache_ios15` 标记时才可恢复。手动“刷新越狱应用”入口保持可用。 |
| 相同 lsd 进程中的重复重建 | 原代码没有单飞或去重逻辑，安装、更新和后续重建可重复排队全量 uicache。 | 使用 `dispatch_once` 对每个 lsd 进程收敛为一次后台刷新；iOS 16 及更高版本仍保留原有自动刷新意图，但不会形成同一进程的重复队列。 |
| 自定义 Boot Logo 资源 | 原代码先删除旧 JP2 后以非原子写入创建新文件；选取原始高分辨率图库图片会在激活阶段再次加载。 | 启动图编码失败时返回错误；使用 `NSDataWritingAtomic` 替换旧资源；选图时统一方向并限制最长边为 2048 px。 |

> 本次没有通过屏蔽看门狗来“消除”告警。看门狗仍会保护真正的 SpringBoard 卡死；修复针对的是安装完成后触发全量 uicache 与 LaunchServices 数据库重建之间的可重入工作链。

Boot Logo 设置界面继续提供参考图所示的 **Enabled**、**Custom Boot Logo** 和 **Select Image** 流程。它在用户空间重启时显示配置的 JP2 启动图，不修改 iBoot、设备固件或冷启动的 Apple 标志；因此不会扩大底层引导风险。选择自定义图片后，图片会保存至应用私有目录，并在下次越狱激活或设置更新时原子刷新到 Jailbreak 根目录。

本轮自动验证新增 `lsd` 防重入、iOS 15 显式启用标记、单飞 gate、Boot Logo 原子写入及 2048 px 上限检查。仍须在 iPhone11,6 / iOS 15.0 上验证新装、覆盖更新、连续更新及手动刷新越狱应用。验收标准是每轮安装完成后 SpringBoard 在正常时限内恢复，且不再进入长时间旋转、Apple 标志或 Dopamine 的 Watchdog Timeout 安全模式。

[5] [RootHide Dopamine2-roothide 2.4.9.25 发布说明](https://github.com/roothide/Dopamine2-roothide/releases/tag/25)

## 追加调查三：首次打开 App、版本同步与自定义壁纸

用户补充的现象将受影响范围扩展到三类相同的恢复边界：新安装 App 完成后、覆盖更新完成后，以及越狱后首次打开可移除应用时。前两类可由 LaunchServices 数据库重建和全量图标刷新重入解释；第三类进一步指向 `launchd` 在可移除 App 第一次 `posix_spawn` 前执行的同步工作。此前已经隔离安装服务和 iOS 15 自动 `uicache`，但 `fix__iosConnect()` 仍在 `launchd` 的首次 App 启动路径同步执行 `IOServiceOpen`。在 iOS 15 arm64e 的临界恢复期，任何 IOKit 连接延迟都会阻塞 pid 1 的启动分派，继而使 SpringBoard 触发看门狗。

本轮确认 RootHide 官方公开 Release `25` 的名称为 `2.4.9.25`，其源分支仍保留旧的 `2.4.8.21` BaseBin 文件版本。因此本分支将构建元数据、Xcode 营销版本和 Release 版本统一为 `2.4.9.25`，以反映官方发布基线并避免 IPA 显示过期版本。[5]

| 文件 | 修改 | 预期作用 |
| --- | --- | --- |
| `BaseBin/launchdhook/src/roothider.m` | 将首次第三方 App 启动中的 IOSurface 连接刷新调整为 iOS 15 arm64e 默认关闭、显式诊断标记 `jbroot:/basebin/.enable_iosurface_refresh_ios15` 才启用。 | 将可选 IOKit 刷新移出 launchd 的默认同步首启关键路径；不影响代码信任、正常注入、手动刷新越狱应用或 iOS 16+ 行为。 |
| `BaseBin/launchdhook/src/roothider.m` | 对带 `_SafeMode` 或 `_MSSafeMode` 的可移除 App，跳过同步 `jbdSpinlockFixOnly` RPC。 | 用户已经明确禁用插件时，不再将新 App 暂停并等待 jailbreakd 的自旋锁远程补丁；正常注入进程仍保留 iOS 15 自旋锁缓解。 |
| `BaseBin/_external/basebin/.version` 与 Xcode 主目标 | 统一为 `2.4.9.25`。 | 生成 IPA 的 `CFBundleShortVersionString` 与当前 RootHide 官方发布名称一致。 |
| `DOUIManager`、`DONavigationController`、`DOSettingsController` | 新增 Custom Wallpaper 开关、图库选图、原子存储、通知刷新与主题图片回退。 | 自定义壁纸仅替换 Dopamine 应用内背景，不触碰系统主屏幕壁纸、iBoot 或用户空间重启核心路径。 |

自定义壁纸复用 Boot Logo 已有的安全策略：图片选择后重新渲染以消除方向元数据，最长边限制为 2048 px，JPEG 以原子方式写入应用 Documents 目录。若没有选择有效图片或关闭开关，主界面无缝回退到当前主题背景；壁纸选择不会参与 `launchd`、dyld、安装服务或自旋锁补丁。

> 自旋锁修复不能被整体关闭：上传的 kernel panic 与 iOS 15 arm64e dyld 共享缓存风险相符。此次修复仅将 **明确安全模式、无插件负载** 的 App 从同步远程补丁中排除，同时保留正常 RootHide 注入进程的原始 spinlock mitigation。

本轮 IPA 回归脚本新增官方版本、IOSurface iOS 15 默认保护、安全模式 spinlock 降级和自定义壁纸通知/偏好键检查。最终设备验收应在 iPhone11,6 / iOS 15.0 上按顺序完成：越狱后首次打开普通 App、安装新 App、覆盖更新同一 App、连续两次更新、再手动“刷新越狱应用”。通过标准是每次操作后 SpringBoard 正常返回且不出现黑屏旋转、Apple 标志或 Dopamine `Watchdog Timeout`；若仍出现 `Spinlock` kernel panic，则需收集新 `.ips` 以区分正常注入进程中的 dyld 共享缓存问题与安装恢复链回归。

## 追加调查五：新增 PAC 跳板崩溃与 SpringBoard 注入兼容性

新增日志补全了此前仅有 watchdog 超时的跳板故障模式。`SpringBoard-2026-08-18-114342.ips` 与 `SpringBoard-2026-08-18-114405.ips` 都是 iOS 15 arm64e 主线程 `EXC_BAD_ACCESS / SIGSEGV`，并明确标记为“possible pointer authentication failure”。两份报告的已加载镜像包含实际第三方动态库：第一份包含 `PassByCC`、`HomeTapBackApp.dylib` 与 `AppData.dylib`，第二份包含 `PassByCC`、`floatingView.dylib` 与 `CraneSB.dylib`。这说明即便用户在故障后进入安全模式，产生 PAC 崩溃的那次 SpringBoard 启动仍然带有第三方注入载荷；日志不能支持“崩溃时没有插件加载”的判断。

14:54 至 15:01 的新增记录还呈现两个完整的 SpringBoard watchdog 对：首次为无成功 check-in 或 60 秒未响应，约一分钟后升级为 120/130 秒未响应并由 watchdogd 诱导重启。这与前一批 03:19、08:13、11:07 的 60/120 秒模式一致，表明一旦跳板主线程进入错误或阻塞状态，系统会经历固定的两阶段恢复过程。

本轮没有重启 `d2fc847` 中会影响越狱激活的核心守护进程全量排除策略。取而代之的是更窄的兼容性修复：在 iOS 15 arm64e 的 SpringBoard 启动中，保留 RootHide 的 `systemhook` 及引导必须路径，但默认将 `DYLD_INSERT_LIBRARIES` 收敛为 systemhook 自身，去除第三方 TweakInject 载荷；如果 SpringBoard 已处于安全模式，则彻底清除该变量，避免外部 tweak loader 继承。只有手动创建 `jbroot:/basebin/.enable_springboard_tweaks_ios15` 才会恢复旧的 SpringBoard 第三方插件注入行为。

该设计的目标是优先让越狱和 SpringBoard 保持可启动，同时保留普通 App、越狱 App 和 RootHide 必需组件的现有注入策略。它针对 PAC 主线程崩溃与 watchdog 的直接证据，不伪造内核稳定性结论；新出现的 `watchdogd` Spinlock panic 仍提示 iOS 15 内核共享缓存问题需按进程与日志继续跟踪。验收应确认 SpringBoard 不再加载 `TweakInject/*.dylib`、不出现 PAC failure、且连续用户空间重启后无 60/120 秒 watchdog pair。

## 追加调查六：21:10 CommCenter 自旋锁与 launchd initproc 恐慌

新提交的两份报告将残余风险收敛为两个独立类别。`panic-full-2026-08-18-211006.000.ips` 是 iOS 15.0 `Spinlock[...] timeout`，被恐慌任务为 `CommCenter`（pid 12549），并出现 `roothide.execpatch.event-queue` 线索；这与此前由 `Aweme`、`symptomsd`、`watchdogd` 出现的共享缓存/自旋锁样本不同，但共同点是平台或普通进程进入了 RootHide 可见的补丁事件范围。`panic-full-2026-08-18-211150.000.ips` 则是 pid 1 `launchd` 的 `initproc exited -- exit reason namespace 2 subcode 0xa`，没有给出足以将退出归因于单一 RootHide 函数的用户态栈；因此不能将它误修为“关闭 launchd 注入”或恢复会阻断越狱的全局守护进程隔离。

本轮只对日志直接点名、且不承载 RootHide 功能的 `/usr/sbin/CommCenter` 做 iOS 15 arm64e 默认降级：不注入 systemhook，也不走同步自旋锁 RPC，直接使用原始 spawn 路径。`launchd`、`watchdogd`、`jailbreakd` 与 userspace reboot 相关服务保持原有路径，避免重现 `d2fc847` 的越狱启动失败。兼容性回退开关为 `jbroot:/basebin/.enable_commcenter_injection_ios15`；仅在需要诊断 CommCenter 注入时才应创建。

本修复降低了已有 CommCenter panic 样本重复经过 RootHide 注入/补丁队列的机会，但不能声称修复所有 iOS 15 内核自旋锁：内核 panic 仍需要在实际设备上通过连续蜂窝网络切换、App 安装更新、userspace reboot 和待机唤醒进行验收。若仍出现 initproc exited，需保留与该次发生相邻的 SpringBoard、watchdog 与完整 panic 日志，以判定是启动过程中的上游系统退出还是可继续缩小的越狱路径。

## 追加调查七：`aggregated` CPU 资源报告

`aggregated.cpu_resource-2026-08-19-040536.ips` 不是 panic、Jetsam 或 watchdog 终止报告，而是 iOS 的 CPU resource report。报告的目标进程为 Apple 系统守护进程 `/System/Library/PrivateFrameworks/AggregateDictionary.framework/Support/aggregated`（pid 4042），在 2026-08-19 04:03:48 至 04:05:33 的 104 秒窗口中使用了 90 秒 CPU 时间，平均 86%；系统只记录该资源异常，明确写明 `Action taken: none`。报告采样期间设备处于闲置、接电和 Background QoS，进程内存占用最高仅 19.67 MB，且没有热压力或低磁盘空间证据。

| 证据 | 可确认的含义 | 不能据此推断的结论 |
| --- | --- | --- |
| `aggregated`、`PowerlogCore`、`PowerlogLiteOperators` | Apple 的功耗/统计收集守护进程正在执行后台聚合工作。 | 不能证明 Dopamine 应用自身占满 CPU。 |
| 高频栈：`PowerlogLiteOperators -> CoreServices -> CoreServicesStore` | 高 CPU 与 CoreServices/LaunchServices 数据库读取、枚举或统计处理相关，时间上可与应用安装、更新或图标数据库变化重叠。 | 由于栈没有私有符号、调用来源或 IPC 发起者，不能证明某一个安装操作是唯一根因。 |
| 无 `roothide`、`jbroot`、`TweakInject` 或 RootHide 动态库命中 | 该单一报告没有显示 RootHide 注入代码在 `aggregated` 中运行。 | 不能仅凭“没有命中”否定系统事件间接触发了后台统计。 |
| `Action taken: none` | 这次异常未被系统按看门狗、Jetsam 或崩溃进行处置。 | 不能把本报告本身当作安全模式的直接原因。 |

因此，不能也不应在 Dopamine 应用内杀死、节流或注入 `aggregated`：它是受系统管理的 Apple 守护进程，强行干预会破坏系统统计，并不能安全地消除内核自旋锁或 SpringBoard 看门狗。应用内可安全处理的只有**避免不必要地触发大规模 LaunchServices 工作**。当前分支已实现该处置：iOS 15 arm64e 的 `LSServer_RebuildApplicationDatabases` 回调默认不自动启动 `uicache -a`；只有创建 `jbroot:/basebin/.enable_auto_uicache_ios15` 才会恢复旧行为，且旧行为仍以每个 `lsd` 进程一次的 `dispatch_once` gate 去重。手动刷新越狱应用入口不受影响。

这意味着该 CPU 报告更像是安装/更新后可能加剧卡顿的**伴随系统负载证据**，而非新的可直接在 App 内“修复”的崩溃根因。安装/更新后应保持 `.enable_auto_uicache_ios15` 不存在；若设备仍在运行旧 IPA，需要安装含该默认保护的当前构建、执行一次 userspace reboot 或重新越狱，再重新采集同一时间窗内的 `aggregated`、`lsd`、SpringBoard、watchdog 及完整 panic 日志进行对比。

[6] [新增 `aggregated` CPU 资源报告（设备现场附件）](../../upload/aggregated.cpu_resource-2026-08-19-040536.ips)

## 追加调查八：启动期全量缓存刷新收敛

对当前构建路径的审计发现，`roothidehooks/lsd.x` 已在 iOS 15 arm64e 默认关闭“数据库重建后自动 `uicache -a`”，但 `jbctl internal startup` 仍会在每一次重新越狱或 userspace reboot 后无条件执行一次同步 `uicache -a`。该启动期刷新不是普通 App Store 应用安装、更新或首次打开所必需；它会让 `lsd` 重建 LaunchServices 数据库，可能与系统自身的安装后 reconciliation、`CoreServicesStore` 扫描及 `aggregated` 的功耗统计工作在同一恢复窗口叠加。

| 路径 | iOS 15 arm64e 新策略 | 保留的能力 |
| --- | --- | --- |
| `LSServer_RebuildApplicationDatabases` 回调 | 继续默认不自动刷新，只有 `.enable_auto_uicache_ios15` 才会恢复旧行为。 | 手动“刷新越狱应用”仍可使用。 |
| `jbctl internal startup` | 新增 `shouldRefreshJailbrokenAppsAtStartup`；默认跳过启动期 `uicache -a`。 | iOS 16+ 维持旧的启动期刷新；iOS 15 需要时可创建 `jbroot:/basebin/.enable_startup_uicache_ios15` 显式恢复。 |
| 用户主动刷新 | 不改变 `DOEnvironmentManager refreshJailbreakApps` 的手动操作。 | 用户可在确认系统空闲时自行刷新越狱应用图标。 |

这项防护不尝试关闭、杀死、节流或注入 Apple 的 `aggregated` 守护进程，也不改变 `launchd`、`watchdogd`、`jailbreakd` 与安装服务的启动路径。它仅移除 iOS 15 恢复窗口中的一项非必要、全局且同步的 LaunchServices 工作，以降低以后安装/更新完成、首次启动或 userspace reboot 后出现 CoreServices/Powerlog CPU 峰值并放大 SpringBoard 看门狗的概率。`.disable_startup_uicache` 同时提供跨版本的显式禁用开关；正常 iOS 15 用户无需创建任何标记文件。

IPA 回归脚本已检查启动期判定函数、iOS 15 显式回退标记和跳过日志文本，防止未来合并时重新引入无条件启动期全量刷新。该优化降低已知可控触发源，不能承诺消除 Apple 内核、Powerlog 或第三方 App 自身导致的所有 CPU 异常；仍须通过真机连续安装、覆盖更新、重新越狱和首次启动验证。

## 追加调查九：越狱工具类 App 的首次启动与 exec 补丁队列

用户补充的受影响样本包括 Filza、Zleaner Pro、KrashKop、Patcher、RootHide、Sileo 与 TrollSpeed。它们不应被简单归为同一个 bundle identifier 或同一个第三方 tweak；共同特征是会在首次前台启动或安装/更新后的初始化中启动辅助可执行文件、调用 `execve`/`POSIX_SPAWN_SETEXEC`，或进行软件包、文件、补丁、网络和越狱环境检查。该模式与普通只显示 UI 的 App 相比，更频繁经过 `systemhook` 的 exec 补丁队列。

审计发现 `spawnExecPatchAdd` 的旧顺序先注册 `NOTE_EXEC` kevent、再使用异步队列写入 pid→resume 记录。工具 App 的辅助进程可以在记录可见前立即 exec；此时事件线程取得无记录的 pid，旧代码还依赖断言处理异常 kevent。结果可能是补丁没有与恢复信号配对，或 jailbreakd 的事件处理路径异常，使后续启动期同步 RPC 堆积并放大为 SpringBoard/watchdog 的长时间恢复。

本轮将记录写入改为同步且位于 kevent 注册之前；若注册失败，立即同步回滚记录。事件循环将 kevent 读取错误和非 `EVFILT_PROC` 事件记录为可恢复错误，而不再依赖断言。该修复的范围是**所有通过 `POSIX_SPAWN_SETEXEC` 执行辅助命令的 RootHide 注入进程**，因此可覆盖这类工具 App 的包管理、清理、文件操作和检测辅助路径，不依赖猜测或硬编码每个 App 名称。

| 风险点 | 修复后行为 | 兼容性影响 |
| --- | --- | --- |
| pid 的 NOTE_EXEC 先于 resume 记录到达 | 注册前同步保存记录。 | 进程仍按原有 RootHide 补丁和 resume 逻辑运行，不跳过必要代码签名或 dyld 处理。 |
| kevent 注册失败 | 同步移除预先建立的记录并向调用方返回错误。 | 不留下会误匹配未来 pid 的陈旧状态。 |
| 异常 kevent | 记录并继续等待后续事件。 | 避免辅助队列因为断言终止，降低启动期后续 RPC 失配。 |

该修复与 iOS 15 自动 `uicache` 收敛、IOSurface 刷新默认关闭、安装服务隔离和 CommCenter 单进程降级互补；它不通过全局关闭 `launchd`、`watchdogd`、TweakInject 或系统守护进程来掩盖问题，因此不重复 `d2fc847` 的越狱启动失败风险。视频未成功上传不会阻碍本次代码级竞态修复；若问题仍复现，后续需要同一时段的 `jailbreakd`、`launchd`、SpringBoard 和 watchdog 日志以确认是否还有未覆盖的同步 RPC 路径。
