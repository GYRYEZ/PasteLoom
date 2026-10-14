# PasteLoom Next Implementation Plan

审计基线：2026-10-05 更新；当前代码 HEAD `681fb14`，其上有未提交 UI、设置与资源改动。八份 Clean-Room 文档及用户截图仍为产品基准。阶段计划用于跟踪实现范围，不表示所有桌面验收已签收；当前可验证状态见 `PASTELOOM_NEXT_CURRENT_STATUS.md`。保持 0.20 秒 Clipboard Monitor 默认值、SQLite 历史、图片指纹唯一索引、单捕获 owner、四类捕获与 Copy Back；不重建真实数据库。交接截图中的旧缺陷与示例数据均不是需要复制的实现。

## Stage 1 — 核心产品体验

Main Drawer、Paper Cards、Source App、Favorite、Pin、Tags、Full Text Search、Theme System 和 Settings Foundation 已有初版。先修卡片/工具栏越界、来源不可靠或为空、标签筛选缺口与主题可读性；用 200 条混合数据测试首尾滚动、窄窗和明暗主题。重启后验证收藏、置顶、标签与原历史仍在。对应 AT01–03、AT09–16、AT19、AT41。已完成的四类捕获和 v5 迁移不重写。

## Stage 2 — 快速工作流

完成 Quick Paste parity、Auto Paste 桌面验收、Keyboard customization、Edge Hover、四向 Edge Dock、多显示器 List/Grid、Cursor Assistant。现有全局键录制、搜索与复制路径只扩展和复验；增加空格多选及悬停预览的边界处理。Dock 可见性、开机启动在本阶段实现，菜单栏历史面板留到 Stage 8。Accessibility 关闭时搜索/Copy Only 仍可用；绝不向无效目标注入 Cmd+V。对应 AT14–18、AT25–29。

## Stage 3 — 截图系统

独立截图服务完成区域/窗口 Screenshot Capture、Quick Screenshot、Annotation、OCR、Save/Copy。标注逐项覆盖矩形、椭圆、箭头、直线、画笔、文字、马赛克与撤销。权限缺失时引导用户授权；取消无剪贴板副作用。OCR 作为可选元数据经单独 schema migration 入库，失败不损坏原图。对应 AT30–33。

## Stage 4 — 数据智能

完成 Semantic Search、来源/类型/文本 Filtering、URL Cleanup、Sensitive Content Protection、Merge、Trash 期限、Retention、Statistics。现有类型排除和 URL 清理继续使用；加入任一/全部多标签、分组基础，并明确富文本/视频范围。敏感内容先定义展示、导出、未来 MCP 的统一脱敏边界，再开放外部能力。语义检索默认本机；模型与资源预算需 `NEEDS USER CONFIRMATION`。对应 AT05、AT07、AT10–13、AT20–21、AT34–35。

## Stage 5 — Rules & Scripts

提供有序规则、条件/动作、模板、手动执行与 Run History。脚本明确导入和授权，失败不阻断普通捕获；自动化不能静默修改原始历史。使用隔离样本验证禁用、重启、执行顺序与错误。对应 AT38。

## Stage 6 — AI / MCP

实现默认关闭的 MCP Server、逐项 Tool Permissions、受限 Tools，以及 Claude Code、Codex CLI、Gemini CLI 的明确配置入口。敏感原文外发需单独授权；关闭后连接与能力均终止。不得复用截图中任何旧产品内部路径或标识。对应 AT39。

## Stage 7 — Sync / Import / Export

先设计可移植备份格式、资产引用和冲突策略（`NEEDS USER CONFIRMATION`），再实现原子 Import/Export。同步默认关闭，依次交付 Local Folder、iCloud、WebDAV、S3；失败不得覆盖本地有效历史。用隔离库验证重复导入、部分失败、断线与重启。对应 AT36–37、AT40。

## Stage 8 — Release Readiness

补齐菜单栏历史面板、About、语言和强调色实际生效、小组件（若列入首发）；清理所有空按钮。执行 AT01–44 适用项、签名/并存安装、多显示器、Accessibility ON/OFF、30 分钟内存与 100 项悬停、完整视觉对比、隔离数据迁移和全量回归。P0 未全部通过前不宣布等价或打发布标签。

## 数据迁移与测试闸门

- **迁移风险 HIGH**：真实 schema v5 含 204 条历史和图片资产。未来每个 schema 变更独立版本化；先对隔离副本做升级、重复启动与中断恢复，再做真实库只读计数和 `quick_check`。不得删库重建或清空历史。
- 每阶段单元测试覆盖纯规则、查询及权限决策；集成测试覆盖 SQLite 升级、资源读写和 Copy Back 类型；真实桌面验证覆盖焦点、系统权限、多显示器、截图与目标应用粘贴。测试报告区分 PASS、FAIL、BLOCKED、未执行。
- 每阶段检查四类捕获、去重、0.20 秒空闲轮询、单 owner、历史保留和数据库完整性。高风险数据操作仅用隔离可丢弃样本库。

## Current verification

- 2026-10-05：从 HEAD `681fb14` 的当前工作树运行 `xcodebuild test`，86 PASS / 0 FAIL；结果 `.xcresult` 汇总为 `Passed`。
- 真实 SQLite：schema v7，`PRAGMA quick_check=ok`，本次读取时 `history_items` 为 291 条。计数是时间点快照，剪贴板捕获会使其变化。
- 固定验收包 `AcceptanceBuild/PasteLoom Next.app` 已从当前构建产物重制、ad hoc 签名并启动。Bundle ID `com.gyryez.pasteloom.next`、名称 `PasteLoom Next` 正确；本次以桌面可访问性树确认主历史列表、卡片操作、设置入口及外观/停靠设置可呈现。
- 此 smoke test 不覆盖完整 Clean-Room / Golden Master 桌面验收；多屏、权限切换、真实 Auto Paste、截图输出、连续运行和所有阶段场景仍须后续逐项验证。没有修改 TCC。
- Old project source, resources and history were not accessed.
