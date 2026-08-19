# RootHide Dopamine 2.2.2.17 自定义重建说明

本工作树以 RootHide 官方发布标签 **`17`（2.2.2.17）** 为唯一 Git 基线建立，未将后续 2.4.x 的整体功能合并进来。[1] 本次修改针对 iOS 15 arm64e 在应用安装、覆盖更新或重新越狱后的首次启动阶段可能出现的 LaunchServices 重建、应用预热和注入同步路径风险；它不禁用系统看门狗，也不修改设备固件、iBoot 或冷启动 Apple 标志。

| 需求 | 实现位置 | 行为与边界 |
| --- | --- | --- |
| 自定义壁纸 | `DOUIManager`、`DONavigationController`、设置控制器 | 从照片库选择图片，统一方向后将最长边限制为 2048 px，以原子 JPEG 写入应用私有目录；仅替换 Dopamine 应用背景。 |
| 自定义启动图 | `UIImage+JPEG2000`、`DOEnvironmentManager`、设置控制器 | 从照片库选择图片，保存为 PNG 并在越狱完成或已越狱时原子导出为 `bootlogo.jp2`；不改动固件或冷启动标志。 |
| 隐藏越狱工具图标 | `DOEnvironmentManager`、设置控制器 | 通过 `uicache -u` 注销 `jbroot:/Applications` 中的越狱工具图标；取消开关后执行一次手动刷新以恢复。该实现**不会**删除 `/var/jb`、不会替换 dyld，也不会改变 RootHide 核心注入状态。 |
| 安装/更新后的稳定性 | `systemhook`、`launchdhook`、`roothidehooks/lsd.x`、`jbctl` | 安装服务不再继承系统注入；iOS 15 arm64e 默认跳过短生命周期预热注入；自动全量 `uicache` 在 iOS 15 改为显式启用，避免 LaunchServices 可重入。 |
| 看门狗恢复安全性 | `watchdoghook`、`jbdomain_watchdog.c` | 仅拦截结构完整、NUL 结束的看门狗文本负载；安全模式标记创建/关闭失败时返回错误，避免恢复路径伤害 `launchd`。 |

> 默认策略是“延后高风险补丁、保留手动恢复入口”。iOS 15 设备上，越狱后仍可通过应用内 **刷新越狱 App** 恢复图标，而无需由 `lsd` 或启动脚本自动触发全量刷新。

## iOS 15 诊断开关

默认情况下，iOS 15 arm64e 不会自动运行两条全量刷新路径。如确有兼容性需求，可在确认设备稳定后创建对应标记，并在下一次相关进程重启后生效。

| 标记路径（相对 `jbroot:`） | 恢复的旧行为 | 默认值 |
| --- | --- | --- |
| `/.enable_auto_uicache_ios15` | LaunchServices 数据库重建后自动 `uicache -a` | 关闭 |
| `/.enable_startup_uicache_ios15` | `jbctl startup` 时自动 `uicache -a` | 关闭 |

上述开关仅用于诊断或有明确需求的设备；如果重新出现长时间转圈、Apple 标志或 `Watchdog Timeout`，应删除标记并先进行用户空间重启。

## 构建与验证

本工作空间为 Linux 环境，没有 `xcodebuild`、`xcrun` 或 iPhoneOS SDK，因此无法在此直接产生可安装的 `.tipa`。源代码已通过差异空白检查、Xcode 工程引用检查，以及全部新增 iOS 15 回归标记检查。最终构建必须使用项目要求的 macOS/Xcode 环境；原仓库也明确将构建入口放在 macOS GitHub Actions 工作流中。[2]

建议在 macOS 14 或与项目一致的 GitHub Actions 运行器中执行构建，并在真机上按以下次序验收：

1. 在 iOS 15.0 arm64e 设备新装一个普通 App，等待至少五分钟后首次打开。
2. 覆盖更新同一 App，再次等待并首次打开；确认 SpringBoard 不转圈、不发生用户空间重启。
3. 重新越狱后先打开一个普通 App，再分别打开文件管理、清理、补丁和包管理类工具。
4. 分别启用/关闭“隐藏越狱工具图标”，确认注销和恢复图标均可完成。
5. 选择自定义壁纸及启动图，确认图片大于 2048 px 时仍能保存，且后续越狱可正常完成。

## 参考资料

[1]: https://github.com/roothide/Dopamine2-roothide/releases/tag/17 "RootHide Dopamine 2.2.2.17（标签 17）"
[2]: https://github.com/qwer12345uui/Dopamine2-roothide/blob/2.x/.github/workflows/roothide.yml "项目 macOS 构建与验证工作流"
