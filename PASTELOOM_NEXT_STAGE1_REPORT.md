# PasteLoom Next Stage 1B Report

> 历史快照（2026-10-04）：此报告准确记录 Stage 1B 当日状态，不代表当前 HEAD。后续实现与 2026-10-05 验收快照见 `PASTELOOM_NEXT_CURRENT_STATUS.md`；旧测试数、schema 与数据计数均不可用于描述当前状态。

日期：2026-10-04。状态：**INCOMPLETE**。这份报告只记录本轮实际构建、自动化和桌面观察，不把代码存在当作桌面验收通过。

## Changes

- 纸卡增加 450 ms 的悬停预览，文本/URL/图片/文件按类型显示；图片仍经有限尺寸的缩略图路径读取。悬停离开、视图消失、点击动作会关闭预览。
- 左侧贴边时发现悬停弹层向屏幕外展开，只剩窄边可见；已改为上下锚点。当前桌面窗口截图未能确认修复后弹层在完整屏幕上的位置，列为待验。
- 搜索词、模式、已选过滤器或组合过滤条件变化时，历史滚动位置回到顶部。实机复查 URL 查询首项不再从半张卡开始。
- 图片标注器标题与默认保存文件名统一为 `PasteLoom Next`；设置文案明确纸卡悬停预览的当前范围。
- 未改变 Clipboard Monitor、SQLite schema、图片指纹去重、单实例捕获或 Copy Back 代码。

## Fixed Acceptance Build

本地 `AcceptanceBuild/PasteLoom Next.app` 已使用当时最新通过测试的构建重新生成、ad hoc 签名并真实启动。该路径为忽略的验收产物，不保留本机绝对路径。Bundle ID 为 `com.gyryez.pasteloom.next`。没有修改 TCC。

## Desktop Validation

| 项目 | 结果 | 证据或限制 |
|---|---|---|
| Main Drawer | PARTIAL | 左侧贴边圆角玻璃抽屉已启动；右/顶/底、多屏、最窄尺寸与长列表完整滚动待验。 |
| Text Card | PASS | 列表显示来源、时间、字数、正文截断及动作。 |
| URL Card | PASS | example.com 卡显示域名、完整 URL；详情预览已打开。 |
| Image Card | PASS | Shottr 图片显示尺寸、大小、缩略图；可进入标注器。 |
| File Card | PASS | 长文件名与路径留在卡片内。 |
| Multi-file Card | PASS | 两个文件为一张卡；详情列出两个可逐项 Quick Look 的文件。 |
| Source App | PARTIAL | ChatGPT 与 Shottr 的名称及图标可见；跨应用新复制和来源过滤未本轮验收。 |
| Favorite | PASS | 测试 URL 收藏、重启保持、取消成功；另以临时收藏核对筛选只显示收藏条目，随后撤销并恢复历史视图。 |
| Pin Core | PASS | 测试 URL 置顶升至列表首位，重启保留，且与收藏、两标签共存；之后取消。 |
| Tags | PASS | 测试 URL 添加两标签、重启保留、从 UI 移除成功。 |
| Tag Search | PARTIAL | 单标签和全文关键词加标签交集命中；多标签 OR/AND 桌面路径待验。 |
| Full Text Search | PARTIAL | URL、普通关键词、与标签交集命中；文件名、来源、日期路径待验。 |
| Preview | PARTIAL | 文本、URL、多文件详情及图片标注入口已打开；单文件 Quick Look、图片详情未逐项打开。 |
| Hover Preview | PARTIAL | 首次出现出屏问题；锚点已调整并构建，完整屏幕弹层、离开关闭、滚动行为需人工确认。 |
| Theme | PARTIAL | 浅/深主窗及设置实测；北欧白桦、黑曜石深邃设计色切换可见；跟随系统已恢复。从 TextEdit 注入 ⌥⌘V 未观察到 Quick Paste 面板，需实体键盘确认是快捷键注册还是测试输入方式问题。 |
| Settings | PARTIAL | 七个顶层页可见、通用外观和布局可操作；其他规划页及权限状态未逐项桌面检查。 |
| List Mode | PARTIAL | 五类卡片、搜索和过滤可用；大历史连续滚动、键盘/多选状态待验。 |
| Screenshot regression | PARTIAL | 历史图片进入标注器，工具栏与新标题显示；Save PNG/Copy Image 本轮未实际输出。全屏捕获权限路径仍需用户验收。 |

测试使用既有 `https://example.com/round25` 记录。初始 `favorite=0`、`pinned=0`、无标签；验收后以 UI 还原，SQLite 再次查询仍为 `0/0/0`。本轮未删除任何历史。用户原有偏好 `themePreset=sunset`、`appearanceMode=system`、`historyLayout=grid` 也已恢复。

## Automated Tests and Data

`xcodebuild build`：PASS。`xcodebuild test`：45 PASS / 0 FAIL。测试涵盖现有捕获、迁移、去重、设置、搜索、预览路由和截图渲染。没有添加纯像素布局测试。SQLite：schema v5，`PRAGMA quick_check=ok`。本轮开始的历史计数 243；末次检查为 248；增长来自运行期间的新复制，没有减少。

## Final Gate

未通过。悬停预览最终位置与关闭条件、Quick Paste 触发及主题、多个内容类型详情路径、密集滚动以及 Settings 规划状态的桌面验收尚未完整签收。依据 Stage 1B 指令，**不声明 Stage 1 COMPLETE，不创建 `pasteloom-next-stage1` tag，也不 push**。Pin 的 Retention 保护留待 Stage 4，不作为当前门槛。

## Follow-up Manual Checks

1. 在固定验收包的**列表模式**，将鼠标停在首张文本、图片、文件卡上约半秒；确认预览完整位于屏幕内、离开即关闭、卡片按钮仍可点、滚动无卡顿。左右两侧停靠各验一次。
2. 在设置切换浅色/深色/跟随系统及两个主题预设，在 TextEdit 用实体键盘按 ⌥⌘V 打开 Quick Paste，确认快捷键触发，以及面板与主窗、搜索、筛选和选中状态同步。
3. 分别打开图片和单文件详情；检查单文件 Quick Look。用至少两种真实 App 新复制内容验证来源。
4. 验证多标签 OR/AND、文件名搜索、长列表滚动和多选底部栏；检查设置七个页面的规划提示。
5. 标注器用一次可恢复的测试图片执行 Save PNG 与 Copy Image，并手工检查结果。屏幕录制授权仍由用户管理。

## Git and Isolation

Stage 1B 实现、视觉审计与矩阵会作为独立的中间提交保存；最终 Stage 1 提交与 tag 尚未创建。旧 PasteLoom / Clipth 项目源码、工程、资源、数据库、构建和 Git 历史均未访问。Deck/Pastory 仅为公开体验参考，未复制源码。
