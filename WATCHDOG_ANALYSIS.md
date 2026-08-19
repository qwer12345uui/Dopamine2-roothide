# iOS 15 安装/更新后 SpringBoard 看门狗分析

## 日志结论

用户提供的 `userspace-panic-1787159810.ips` 记录的设备为 **iPhone11,6（A12 arm64e）**、**iOS 15.0（19A346）**。日志明确指出：

> `no successful checkins from SpringBoard in 180 seconds`

因此，触发条件不是普通应用本身在启动时崩溃，而是 **SpringBoard 连续 180 秒未向 watchdogd 报到**。同一记录中 `backboardd`、`mediaserverd`、`logd`、`runningboardd` 与 `wifid` 均继续报到，说明这是 SpringBoard 的局部主循环/关键工作线程卡住，而非全局 userspace 已经停止。

日志同时说明 Dopamine 拦截了最终 panic，并执行了一次 userspace reboot。这解释了“安装或更新 App 后数分钟自动重启用户空间”的现象，但拦截并不能消除 SpringBoard 原本的 180 秒无响应。

该 IPS 不包含被阻塞线程的用户栈，因此不能只凭这一份日志把根因断言为单一函数。当前修复以减少安装更新后会在 SpringBoard 或 LaunchServices 中放大为同步、递归工作链的 RootHide 路径为目标。

## 本次修复

| 区域 | iOS 15 arm64e 默认行为 | 目的 |
|---|---|---|
| SpringBoard RootHide hooks | 不初始化 `sb.x` 的 FBSApplicationLibrary、FBSystemService、SplashBoard/fcntl 钩子 | 避免在图标/快照重建期间同步拦截 FBS 与文件保护类调用 |
| LaunchServices 全插件过滤 | 不递归重写 `LSPlugInQueryAllUnits` | 避免安装更新期间将 lsd 查询重新带入自身的可重入过滤链 |
| 自动 `uicache -a` | 保持 iOS 15 默认关闭 | 防止 LaunchServices 数据库重建回调再次触发数据库重建 |
| 安装服务注入 | 保持 `installd`、`appstored`、`storekitd` 与 `mobile_installation_proxy` 排除 | 使安装事务不继承系统注入与挂起子进程路径 |

若因兼容性确实需要恢复旧行为，可手动创建下列 marker；它们默认不存在，不会影响本次稳定性策略。

| Marker | 恢复的旧行为 |
|---|---|
| `/var/jb/.enable_ios15_springboard_roothidehooks` | 在 iOS 15 SpringBoard 加载 RootHide 专属 hooks |
| `/var/jb/.enable_ios15_lsd_recursive_filter` | 在 iOS 15 恢复递归插件单元过滤 |
| `/var/jb/.enable_auto_uicache_ios15` | 在 iOS 15 LaunchServices 数据库重建后恢复自动 `uicache -a` |

## 回归步骤

1. 在已越狱 iOS 15.0 arm64e 设备上安装本版本后执行一次正常越狱。
2. 依次安装一个新 App 与更新一个既有 App；每个操作结束后保持设备解锁并正常使用至少 10 分钟。
3. 在此期间打开两个普通 App、返回主屏，并滑动经过原越狱工具所在的图标页。
4. 不应发生无交互的 userspace reboot、SpringBoard 长时间无响应或新的 `no successful checkins from SpringBoard in 180 seconds` 记录。
5. 若问题仍出现，请一并导出同一时间段的 `.ips`、`panic-full`（如存在）及 `/var/jb/var/mobile/Library/Logs` 下的 RootHide 日志；其中最有价值的是 SpringBoard 与 lsd 的触发时刻、进程栈和重复服务名。

## 约束

本次构建可以验证代码编译和 IPA 打包，但必须在目标 iOS 15.0 设备完成上述安装/更新复测才能确认该设备上的运行期稳定性。
