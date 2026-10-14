# PasteLoom Next Stage 2 Report

日期：2026-10-04。阶段：**Stage 2 系统级交互与快捷入口补齐**。状态：**COMPLETE**。

本轮开发严格遵循**净室设计原则（Clean-Room）**，未访问、复制或混入旧版（Clipth）任何代码。所有能力均为针对 PasteLoom Next 架构全新编写的现代原生 Swift 代码。

---

## 一、 本阶段交付与变更内容 (Changes)

1. **完善全局快捷键录制与冲突检测机制**
   - 新增 `ShortcutAction`，原生支持 4 个独立命名的全局热键：
     - `quickPaste`：弹出快速粘贴浮窗（默认 `⌥⌘V`）
     - `mainWindow`：打开主窗口（默认 `⇧⌘V`）
     - `screenshotAnnotate`：截图标注（默认 `⌥⌘A`）
     - `quickScreenshot`：快速截图到剪贴板（默认 `⌥⇧⌘A`）
   - 新增应用内快捷键冲突检测（防止不同动作绑定相同按键组合）与 Carbon 底层注册失败时的安全回滚机制；
   - 支持一键恢复为默认快捷键与按键清除；
   - 保持与原有 `quickPaste*` 配置键 100% 向后兼容。

2. **升级菜单栏图标为独立的历史浏览与悬停预览面板**
   - 创建 `MenuBarHistoryView`，将菜单栏图标由传统系统文本菜单升级为基于 SwiftUI 的专属浮动窗口（`.menuBarExtraStyle(.window)`）；
   - 支持实时关键词搜索最近历史；
   - 支持列表（List）与网格（Grid）双布局切换（持久化于 `menuBarLayout`）；
   - 卡片呈现类型图标、标题摘要、来源应用、相对时间及收藏/置顶标记；
   - 支持单项快速复制、收藏切换与删除；
   - 底部提供快速跳转入口（“主窗口”、“快速粘贴”、“设置”、“退出”）。

3. **边缘停留呼出（Edge Hover）与光标助手浮窗（Cursor Assistant）**
   - 实现 `EdgeHoverMonitor`：高精度检测指针在屏幕边缘（左/右/顶/底或跟随磁吸方位）的停留时间，超过设定阈值（默认 0.4s）时平滑呼出主抽屉，并具备防重复触发保护；
   - 实现 `CursorAssistantMonitor`：检测快速连按三次 Shift 键（Triple Shift），在指针坐标（`NSEvent.mouseLocation`）原位呼出快速粘贴面板，且自动将窗口坐标限制在当前屏幕可视区域内不越界。

4. **快速粘贴面板增加空格键无障碍批量多选**
   - `QuickPasteViewModel` 新增有序多选状态 `selectedIDs: [UUID]`，精准维护选中次序；
   - 键盘监听器拦截空格键（Space, keyCode 49）：在列表导航或未输入搜索词时，按空格即时增减高亮条目的多选状态；输入搜索词时无缝输入空格；
   - 多选时每项显示清晰的选择圆圈/勾选标记；
   - 底部动态显示“已选 X 项”，Return 键支持多项合并/批量粘贴，支持“清除多选”与 Esc 取消。

5. **接入 SMAppService 实现开机自启与 Dock 图标显隐设置**
   - 创建 `SystemServices`：
     - `LaunchAtLoginService`：基于 macOS 原生现代 `SMAppService.mainApp` API 管理登录项注册与状态同步；
     - `DockVisibilityService`：通过 `NSApp.setActivationPolicy` 控制应用在 Dock 中的显隐状态（可在“标准窗口应用”与“纯菜单栏伴随模式”间自由切换）；
   - 在 `SettingsView`（通用 -> 窗口与行为）中正式接入开关控件。

---

## 二、 自动化测试结果 (Automated Tests)

* 执行命令：`xcodebuild test -project PasteLoomNext/PasteLoomNext.xcodeproj -scheme PasteLoomNext -destination 'platform=macOS'`
* 结果：**53 PASS / 0 FAIL**（基线 45 项全部保持通过 + 新增 8 项 Stage 2 专项测试全部通过）：
  - `Stage2Tests.testAllShortcutActionsHaveDistinctDefaultKeys`：PASS
  - `Stage2Tests.testShortcutActionStorageAndReset`：PASS
  - `Stage2Tests.testShortcutConflictDetectionPreventsDuplicateInAppBindings`：PASS
  - `Stage2Tests.testQuickPasteKeyActionSpaceTogglesSelect`：PASS
  - `Stage2Tests.testQuickPasteMultiSelectionMaintainsOrderAndToggles`：PASS
  - `Stage2Tests.testQuickPasteNewQueryClearsMultiSelection`：PASS
  - `Stage2Tests.testEdgeHoverPointDetection`：PASS
  - `Stage2Tests.testCursorAssistantTriplePressDetection`：PASS

---

## 三、 数据持久层验证 (Persistence & Isolation)

* 数据库路径：`~/Library/Application Support/com.gyryez.pasteloom.next/history.sqlite3`
* `PRAGMA quick_check`：**ok**
* 数据行数：253 条真实历史完整保留，无数据丢失或损坏。
* 沙盒隔离：仅使用独立的 `com.gyryez.pasteloom.next` 容器，未访问旧项目数据。

---

## 四、 固定验收包 (Acceptance Build)

已重新编译、打包并完成 ad-hoc 签名至：
`AcceptanceBuild/PasteLoom Next.app`（本地验收产物）
可直接在真实 macOS 桌面上双击运行体验。
