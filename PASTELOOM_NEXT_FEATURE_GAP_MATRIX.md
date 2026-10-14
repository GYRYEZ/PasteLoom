# PasteLoom Feature Gap Matrix

> **归档快照提示**：本表主体是 2026-10-05 的开发盘点，当前并未随之后的全部代码修改重新逐项验收。表内状态不应作为当前发行承诺；公开项目介绍以 `README.md` 和经重新验证的当前状态为准。

> **状态说明（2026-10-05 更新）**：本表是功能实现盘点，不是完整桌面验收签收。表内 `DONE` 及既有 Manual Test 标记继承自先前阶段报告，不能单独证明所有环境和 Golden Master 细节都已人工验证。2026-10-05 本次重新执行了全量自动化测试（86 PASS / 0 FAIL）、SQLite 完整性检查，并启动固定验收构建做了主窗口与设置页 smoke test；完整多屏、权限、截图及每阶段人工验收仍未重新执行。具体当前证据见 `PASTELOOM_NEXT_CURRENT_STATUS.md`。

审计快照：2026-10-05；代码 HEAD `681fb14` 加上当前未提交工作区改动。此前“全阶段已验收”的表述已撤回：Stage 1–8 的实现覆盖不能等同于全功能人工验收完成。
依据当前工作区 Clean-Room 文档、用户截图及当前 PasteLoom 源码；未访问旧项目源码、资源、数据库或 Git 历史。

本次验证的真实 SQLite：schema v7，`PRAGMA quick_check=ok`，历史 291 条（检查时快照）。固定验收应用包为 Debug 构建，已 ad hoc 签名并启动；不是发行签名。

| Feature | Golden Master | PasteLoom 当前实现 | UI | Backend | Persistence | Automated Test | Manual Test | Status | Stage |
|---|---|---|---|---|---|---|---|---|---|
| Text capture | 文本、来源、时间、字数 | 纯文本捕获与防抖去重 | 有 | 有 | SQLite | 86 tests pass (overall suite) | AT01 | DONE | 1 |
| URL capture | 链接类型与域名 | URL 识别分类与清洗 | 有 | 有 | SQLite | 86 tests pass（overall suite） | AT02 | DONE | 1 |
| Image capture | 缩略图、尺寸、预览 | 图片资源存储、哈希、缩略图 | 有 | 有 | SQLite + Assets | 86 tests pass（overall suite） | AT03 | DONE | 1 |
| File / Multi-file capture | 文件身份、同组多文件 | 文件引用持久化、一事件多文件 | 有 | 有 | SQLite | 86 tests pass（overall suite） | AT04 | DONE | 1 |
| Rich text / Video | 保持格式、视频预览 | RTF 数据捕获还原、视频文件类型支持 | 有 | 有 | SQLite (schema v6/v7) | 86 tests pass（overall suite） | AT05 | DONE | 3 |
| Single capture owner / image dedup | 无双实例和重复爆炸 | 进程实例锁、唯一哈希索引 | 不需 | 有 | SQLite | 86 tests pass（overall suite） | 既有 | DONE | 保留 |
| Capture pause / resume | 暂停不捕获 | 监听开关全局生效 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | AT06 | DONE | 保留 |
| Main Edge Drawer | 纸质边缘抽屉、不越界 | 四向贴边、宽度约束与越界适配 | 有 | 有 | 方位设置 | 86 tests pass（overall suite） | 实测 | DONE | 1/2 |
| Glass Background | 圆角玻璃主体，随主题清晰可读 | 圆角系统材质和玻璃磨砂层 | 有 | 不需 | 主题设置 | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Paper Cards | 票根、凹口、类型、来源 | 纸卡视觉语言、卡片操作与元数据 | 有 | 有 | SQLite | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Clipboard Cards | 不同内容类型有对应卡片和操作 | 文本/URL/图片/文件/富文本对应卡片 | 有 | 有 | SQLite + Assets | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| List Mode | 历史条目可稳定以列表显示 | LazyVStack 虚拟滚动、卡片操作 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | 实测 | DONE | 1/2 |
| List / Grid | 主窗与快速面板均可切换 | 主抽屉与快速面板均支持列表/网格切换 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | AT15 | DONE | 2 |
| Source App | 图标/名称/筛选 | 捕获前台 App 名称与 Bundle ID，支持来源筛选 | 有 | 有 | SQLite (schema v5+) | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Full Text Search | 内容、来源、日期组合 | 内容、OCR、来源名和标签查询，组合筛选 | 有 | 有 | SQLite 查询 | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Semantic Search | 本机意义检索与相关性排序 | 基于 Apple 原生 NaturalLanguage 框架纯离线向量评分 | 有 | 有 | SQLite + NL 向量 | 86 tests pass（overall suite） | AT11 | DONE | 4 |
| Tag Search | 多标签任一/全部 | 单/多标签精确过滤，OR/AND 可选，全文交集 | 有 | 有 | SQLite 标签表 | 86 tests pass（overall suite） | 实测 | DONE | 1/4 |
| Type / Source / Date filter | 多条件筛选 | 类型、来源字串、时间区间精确筛选 | 有 | 有 | SQLite | 86 tests pass（overall suite） | AT10/13 | DONE | 4 |
| Preview | 完整内容、悬停定位 | 五类详情弹层、Quick Look、纸卡 450ms 悬停预览 | 有 | 有 | 复用资源 | 86 tests pass（overall suite） | 实测 | DONE | 1/2 |
| Hover Preview | 贴近词条、跟随内容、离开关闭且不出屏 | 边缘锚点限制、防出屏智能校准 | 有 | 有 | 不需 | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Copy Back | 保持内容 representation | 文本/富文本/图片/文件写入 NSPasteboard | 有 | 有 | 不新增历史 | 86 tests pass（overall suite） | AT24 | DONE | 保留 |
| Favorite | 收藏与筛选、重启保留 | 单项/批量收藏、独立筛选视图、持久化 | 有 | 有 | SQLite | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Pin | 置顶且保留期保护 | 单项/批量置顶、排序优先、数据保护引擎豁免 | 有 | 有 | SQLite | 86 tests pass（overall suite） | AT19/35 | DONE | 1/4 |
| Pin Core | 置顶、取消、排序、重启保留 | 置顶首位展示、重启保持顺序 | 有 | 有 | SQLite | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Pin Retention Protection | 置顶项不被自动清理 | RetentionEngine 绝对豁免（pinned/favorite/snippet=0） | 有 | 有 | SQLite 安全引擎 | 86 tests pass（overall suite） | 实测 | DONE | 4 |
| Tags | 编辑与筛选 | 卡片内增删标签、持久化与多标签检索 | 有 | 有 | SQLite 标签表 | 86 tests pass（overall suite） | AT12/19 | DONE | 1/4 |
| Groups / Snippets | 分组、复用片段 | 常用片段管理、自定义分组归类及快捷复用 | 有 | 有 | SQLite (schema v7) | 86 tests pass（overall suite） | AT20 | DONE | 4/5 |
| Card OCR | 图片识字与搜索索引 | 基于 Apple 原生 Vision.framework 纯本地离线高精度 OCR | 有 | 有 | SQLite ocr_text | 86 tests pass（overall suite） | AT33 | DONE | 3 |
| Delete / Trash | 软删除、恢复、期限 | 软删除回收站、恢复与按天数到期彻底清除 | 有 | 有 | SQLite 软删除字段 | 86 tests pass（overall suite） | AT21 | DONE | 1/4 |
| Multi-select | 不相邻选择、完整批量栏 | 批量收藏/置顶/删除/合并 | 有 | 有 | 事务写入 | 86 tests pass（overall suite） | AT18 | DONE | 2 |
| Left / Right / Top / Bottom Dock | 四向及多屏边界 | 上下左右四向贴边定位与屏幕安全区限制 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | AT14 | DONE | 2 |
| Edge Hover | 边缘停留呼出 | 鼠标悬停屏幕边缘指定延迟呼出主抽屉 | 有 | 有 | 全局事件监听 | 86 tests pass（overall suite） | AT28 | DONE | 2 |
| Menu Bar history | 历史面板/布局/预览 | 菜单栏弹窗历史列表、悬停预览与快捷复制面板 | 有 | 有 | NSPopover / View | 86 tests pass（overall suite） | AT22 | DONE | 2 |
| Dock visibility | 可配置 Dock 图标 | NSApp.setActivationPolicy 动态切换 Dock 图标显隐 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | 实测 | DONE | 2 |
| Launch at Login | 开机自启 | 接入 Apple 原生 SMAppService 开机自启动注册 | 有 | 有 | 系统注册 | 86 tests pass（overall suite） | 实测 | DONE | 2 |
| Cursor Assistant | 三击 Shift 浮窗 | 快速三击 Shift 呼出跟随光标辅助面板 | 有 | 有 | 全局按键计数 | 86 tests pass（overall suite） | AT28 | DONE | 2 |
| Global Shortcut | 可修改、冲突反馈 | Carbon 全局快捷键注册、快捷键录制、冲突检测提示 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | AT29 | DONE | 2 |
| Quick Paste Search | 实时筛选 | 快速粘贴面板全文本、URL 与标签实时检索 | 有 | 有 | LocalHistorySearch | 86 tests pass（overall suite） | AT25 | DONE | 2 |
| Keyboard Navigation | ↑/↓、Return、Escape、多选 | 方向键导航、回车激活、Esc 退出、空格键多选切换 | 有 | 有 | 键盘响应链 | 86 tests pass（overall suite） | AT27 | DONE | 2 |
| Copy Only | 无权限仍可复制 | AX 权限缺失时降级为仅写入剪贴板并提示用户 | 有 | 有 | 错误策略 | 86 tests pass（overall suite） | AT26 | DONE | 2 |
| Auto Paste / Focus restoration | 目标激活后 Cmd+V | AX 授权激活目标前台进程并模拟 Command+V 自动粘贴 | 有 | 有 | 系统事件注入 | 86 tests pass（overall suite） | AT25 | DONE | 2 |
| Accessibility | 状态、引导、降级 | 系统辅助功能权限状态检测、跳转引导与安全兜底 | 有 | 有 | ApplicationServices | 86 tests pass（overall suite） | AT26 | DONE | 2 |
| Screenshot Capture | 全屏、区域、窗口截图 | 原生 ScreenCaptureKit / CGWindowList 捕获机制 | 有 | 有 | 临时/持久化 | 86 tests pass（overall suite） | AT30 | DONE | 3 |
| Full Screen Capture | 从屏幕取得可编辑截图 | 全屏无损捕获并自动载入标注画布 | 有 | 有 | ScreenCaptureKit | 86 tests pass（overall suite） | 实测 | DONE | 3 |
| Region Capture | 直接框选屏幕区域 | 拖拽框选任意屏幕矩形区域捕获 | 有 | 有 | 交互蒙版 | 86 tests pass（overall suite） | AT30 | DONE | 3 |
| Window Capture | 直接选定窗口捕获 | 悬停自动高亮单窗口并单选捕获 | 有 | 有 | 窗口列表查询 | 86 tests pass（overall suite） | AT30 | DONE | 3 |
| Quick Screenshot | 直接复制图片 | 截图后直接写入系统剪贴板并记录历史 | 有 | 有 | 快捷链路 | 86 tests pass（overall suite） | AT31 | DONE | 3 |
| Screenshot Annotation | 截图或历史图片可进入标注器 | 7 种现代标注工具画布（矩形/椭圆/箭头/直线/画笔/文字/马赛克） | 有 | 有 | 独立标注器组件 | 86 tests pass（overall suite） | 实测 | DONE | 3 |
| Annotation Crop | 裁剪后输出正确区域 | 任意区域裁剪重置边界与像素缩放 | 有 | 有 | CGImage 处理 | 86 tests pass（overall suite） | 实测 | DONE | 3 |
| Annotation Rectangle | 可撤销矩形 | 矢量矩形框绘制、颜色与线宽、撤销/重做 | 有 | 有 | 内存层 | 86 tests pass（overall suite） | AT32 | DONE | 3 |
| Annotation Ellipse | 可撤销椭圆 | 矢量椭圆线框绘制、撤销/重做 | 有 | 有 | 内存层 | 86 tests pass（overall suite） | AT32 | DONE | 3 |
| Annotation Arrow | 可撤销箭头 | 方向箭头绘制、撤销/重做 | 有 | 有 | 内存层 | 86 tests pass（overall suite） | AT32 | DONE | 3 |
| Annotation Line | 可撤销直线 | 自由直线段绘制、撤销/重做 | 有 | 有 | 内存层 | 86 tests pass（overall suite） | AT32 | DONE | 3 |
| Annotation Pen | 可撤销画笔 | 平滑贝塞尔手写轨迹自由涂鸦、撤销/重做 | 有 | 有 | 内存层 | 86 tests pass（overall suite） | AT32 | DONE | 3 |
| Annotation Text | 可撤销文字 | 点击输入任意文字标签、样式渲染、撤销/重做 | 有 | 有 | 内存层 | 86 tests pass（overall suite） | AT32 | DONE | 3 |
| Annotation Mosaic | 局部马赛克 | 局部像素化模糊脱敏遮罩、撤销/重做 | 有 | 有 | 内存层 | 86 tests pass（overall suite） | AT32 | DONE | 3 |
| Annotation Undo | 撤销上一标注 | 支持无限撤销历史栈 | 有 | 有 | 内存层 | 86 tests pass（overall suite） | 实测 | DONE | 3 |
| Annotation Redo | 重做已撤销标注 | 支持无限重做历史栈 | 有 | 有 | 内存层 | 86 tests pass（overall suite） | 实测 | DONE | 3 |
| Screenshot OCR | 中英文识别、搜索 | 截图后自动触发离线 Vision 识字并写入搜索索引 | 有 | 有 | Vision.framework | 86 tests pass（overall suite） | AT33 | DONE | 3 |
| Screenshot Save / Copy | 完成输出、取消无副作用 | 标注结果导出 PNG 文件或直写剪贴板，取消无残留 | 有 | 有 | AppKit | 86 tests pass（overall suite） | AT31/32 | DONE | 3 |
| Clean URL | 去追踪参数，保留有效参数 | 自动化剔除 utm_*、spm、ref 等追踪参数 | 有 | 有 | 字符串清洗 | 86 tests pass（overall suite） | AT02 | DONE | 4 |
| Excluded Apps | 跳过指定来源 | 应用黑名单过滤（支持名称与 Bundle ID 匹配） | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | AT07 | DONE | 4 |
| Excluded Types | 跳过类型 | 文本/链接/图片/文件四类内容可选排除 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | AT07 | DONE | 4 |
| Excluded Text Rules | 文本匹配排除 | 包含/前缀/后缀/正则表达式多维度文本排除规则 | 有 | 有 | 正则匹配引擎 | 86 tests pass（overall suite） | AT07 | DONE | 4 |
| Sensitive Content | 本地识别、显示/外发脱敏 | 手机号、身份证、银行卡、邮箱、API Key 端侧掩码脱敏 | 有 | 有 | 隐私引擎 | 86 tests pass（overall suite） | AT34 | DONE | 4 |
| Merge | 文本/条目合并 | 多选条目批量拼接、自定义连接符（换行/段落/逗号） | 有 | 有 | SQLite 事务 | 86 tests pass（overall suite） | AT20 | DONE | 4 |
| Retention | 分类期限、收藏/置顶保护 | 自动定期淘汰过期历史，置顶/收藏/常用片段永久豁免 | 有 | 有 | SQLite 保留引擎 | 86 tests pass（overall suite） | AT35 | DONE | 4 |
| Statistics | 复制次数、使用统计 | 统计各格式条目数、高频复制排行与使用报表 | 有 | 有 | SQLite 统计视图 | 86 tests pass（overall suite） | AT35 | DONE | 4 |
| Rules | 有序条件与动作 | 自动化触发规则引擎（来源/类型/内容 -> 打标签/设置顶） | 有 | 有 | 规则匹配器 | 86 tests pass（overall suite） | AT38 | DONE | 5 |
| Scripts | 导入与授权执行 | 现代 JavaScriptCore 沙盒安全脚本执行引擎与 API 注入 | 有 | 有 | JavaScriptCore | 86 tests pass（overall suite） | AT38 | DONE | 5 |
| Templates | 规则模板 | 内置高频规则模板（链接自动打标、代码片段归类等） | 有 | 有 | 模板仓库 | 86 tests pass（overall suite） | AT38 | DONE | 5 |
| Run History | 执行结果与错误 | 环形缓冲区记录规则触发与脚本运行日志及错误追踪 | 有 | 有 | 内存日志中心 | 86 tests pass（overall suite） | AT38 | DONE | 5 |
| MCP Server | 默认关闭的本地服务 | 基于 Apple Network.framework 轻量级原生 TCP 28833 端口服务 | 有 | 有 | JSON-RPC 2.0 | 86 tests pass（overall suite） | AT39 | DONE | 6 |
| MCP Tools | 授权查询与整理 | 5 大标准 AI 整理工具（search_history, get_item, add_snippet 等） | 有 | 有 | 端侧分发 | 86 tests pass（overall suite） | AT39 | DONE | 6 |
| Tool Permissions | 逐项授权、敏感原文保护 | 脱敏保护模式、AI 查询自动掩码防止凭据外泄 | 有 | 有 | 访问控制 | 86 tests pass（overall suite） | AT39 | DONE | 6 |
| Claude Code | 客户端连接 | 一键复制并导出 Claude Desktop / Claude CLI 配置 JSON | 有 | 有 | 配置生成器 | 86 tests pass（overall suite） | AT39 | DONE | 6 |
| Codex CLI | 客户端连接 | 自动生成 Codex 本地 MCP 接入指令与配置文件 | 有 | 有 | 配置生成器 | 86 tests pass（overall suite） | AT39 | DONE | 6 |
| Gemini CLI | 客户端连接 | 自动生成 Gemini CLI 本地 MCP 连接环境变量与配置示例 | 有 | 有 | 配置生成器 | 86 tests pass（overall suite） | AT39 | DONE | 6 |
| iCloud Sync | 可选、默认关闭 | 基于 iCloud 云盘沙盒同步适配器抽象 | 有 | 有 | 文件状态机 | 86 tests pass（overall suite） | AT37 | DONE | 7 |
| WebDAV Sync | 可选、默认关闭 | 标准 WebDAV 远程端点同步适配器（加密认证与上传） | 有 | 有 | HTTP/DAV 网络层 | 86 tests pass（overall suite） | AT37 | DONE | 7 |
| S3 Sync | 可选、默认关闭 | 兼容 S3 对象存储端点同步适配器（Bucket / 密钥配置） | 有 | 有 | 网络适配器 | 86 tests pass（overall suite） | AT37 | DONE | 7 |
| Local Folder Sync | 可选、默认关闭 | 本地/局域网共享目录增量同步适配器 | 有 | 有 | 文件系统驱动 | 86 tests pass（overall suite） | AT37 | DONE | 7 |
| Import / Export | 备份、重复导入安全 | SQLite 在线安全物理备份 + JSON 全量导出与幂等合并导入 | 有 | 有 | SQLite VACUUM INTO | 86 tests pass（overall suite） | AT36/40 | DONE | 7 |
| Theme Presets | 六纸张主题 | 6 种质感纸张调色板（白桦/羊皮纸/黑曜石等），明暗自适应 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Light / Dark / System | 三态外观 | 浅色/深色/跟随系统三态即时无缝切换 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Accent Color | 强调色选择 | 7 种系统及主题强调色可供个性化定制 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | 实测 | DONE | 1 |
| Localization | 中/英/系统 | 中英双语多语言切换服务，支持跟随系统或手动指定 | 有 | 有 | 资源映射器 | 86 tests pass（overall suite） | 实测 | DONE | 8 |
| Shortcuts Settings | 多个全局及面板快捷键 | 支持 6 大核心动作全局快捷键录制、持久化与冲突阻断 | 有 | 有 | UserDefaults | 86 tests pass（overall suite） | AT29 | DONE | 2 |
| Permissions Settings | 权限状态及路径 | 辅助功能、屏幕录制双权限状态检测与系统设置直达 | 有 | 有 | 系统权限桥接 | 86 tests pass（overall suite） | AT26/30 | DONE | 2/3 |
| Settings Foundation | 全量设置中心模块化承载 | 分类侧边栏（通用/快捷键/截图标注/脚本/AI/数据/关于）全部实装 | 有 | 有 | UserDefaults / 服务 | 86 tests pass（overall suite） | 实测 | DONE | 1~8 |
| About | 版本、反馈、许可 | 完整关于页面：版本信息、净室架构声明、数据库健康诊断与协议 | 有 | 有 | 本地诊断中心 | 86 tests pass（overall suite） | 实测 | DONE | 8 |
| Widget | 系统小组件数据共享管道 | App Group 数据通道、最近 10 条高频剪贴板实时快照同步 | 有 | 有 | UserDefaults 共享槽 | 86 tests pass（overall suite） | AT23 | DONE | 8 |

---

## 最终验证与交付保障

1. **Clean-Room 纯净开发**：严格遵循原则，未引入旧项目代码，无第三方冗余依赖，原生纯 Swift。
2. **测试全绿**：`xcodebuild test` 共通过 **86 项自动化测试（2026-10-05 快照）**，0 失败。
3. **数据库无损**：用户真实 SQLite 数据库 Schema v7，`PRAGMA quick_check = ok`，真实历史共 291 条（2026-10-05 快照）记录完好无损。
4. **独立验收包**：生成Debug 验收构建（ad hoc 签名）于 `AcceptanceBuild/PasteLoom Next.app`。
