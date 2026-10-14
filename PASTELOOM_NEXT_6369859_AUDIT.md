# PasteLoom Next — 6369859 收口审计

日期：2026-10-04。功能基线为 `6369859`；当前工作区 HEAD 在审计开始时为 `3b4c286`，该后续提交只补充截图权限设置状态显示。本报告不把后续修复归入 `6369859`，也不把 UI 入口等同于功能验收。状态 `WORKING` 表示源码、持久化和相关自动测试支持现有能力，仍可能需人工确认；`PARTIAL` 表示 Golden Master 范围或验收缺口；`MISSING` 表示未实现。

## Stage 1

| 项目 | 状态 | 依据与剩余缺口 |
|---|---|---|
| Main Drawer | PARTIAL | 已贴边、四向定位和屏幕边界约束；多显示器、边缘交互与视觉验收不足。 |
| Paper Cards | PARTIAL | 文本、URL、图片、文件卡片及操作已接入；票根细节、拥挤布局和长列表视觉验收不足。 |
| Source App | WORKING | 新记录读取前台应用身份，经 schema v5 保存并显示；旧记录来源保持未知。真实跨应用来源仍待 AT01/13。 |
| Favorite | WORKING | 收藏、筛选和重启读取有实现及测试；待桌面 AT19。 |
| Pin | PARTIAL | 置顶、排序与持久化存在；Golden Master 的保留期保护未实现。 |
| Tags | PARTIAL | 添加、编辑、移除、持久化与单标签查询存在；多标签任一/全部尚缺。 |
| Full Text Search | WORKING | 内容、URL、文件名、来源和标签关键词查询已接入同一搜索层并测试；组合场景待 AT10。 |
| Tag Search | PARTIAL | 单标签可查询；OR/AND 多标签组合未实现。 |
| Theme System | WORKING | 六预设、明暗/跟随系统和强调色设置已接入并持久化；实际可读性待 AT16/41。 |
| Settings Foundation | PARTIAL | 主设置和若干分类页面可用；部分 Golden Master 设置仍为占位，权限设置在 `3b4c286` 才补充屏幕录制状态。 |
| Naming Consistency | WORKING | 当前产品界面和应用身份使用 PasteLoom Next；仍需完整桌面文案巡检。 |
| Existing Preview | PARTIAL | 文本详情、图片及文件 Quick Look 路径存在；悬停预览及定位尚缺。 |
| List Mode | PARTIAL | 主窗列表切换存在；密集历史、窗口尺寸及视觉对齐待验。 |

**Stage 1 Complete：NO。** 提前加入截图标注不能替代卡片、抽屉、标签组合、设置及预览的剩余工作。

## Screenshot

| 项目 | 状态 | 依据与剩余缺口 |
|---|---|---|
| Screenshot Capture / Full Screen Capture | PARTIAL | ScreenCaptureKit 整屏路径存在；当前构建的系统授权检查仍拒绝捕获，需人工验收。差距矩阵标为 `NEEDS MANUAL VALIDATION`。 |
| Region Capture | MISSING | 编辑器 Crop 不等于截图前区域选择。 |
| Window Capture | MISSING | 未实现窗口选择。 |
| Annotation | PARTIAL | 历史图片可进入编辑器，工具与输出路径已接入；逐工具真实桌面验收未完成。 |
| Crop | PARTIAL | 实现及像素测试存在，桌面输出待验。 |
| Rectangle | PARTIAL | 实现存在，旧图片绘制曾观察到；完整撤销/输出待验。 |
| Ellipse | PARTIAL | 实现存在，待独立桌面验收。 |
| Arrow | PARTIAL | 实现存在，待独立桌面验收。 |
| Line | PARTIAL | 实现存在，待独立桌面验收。 |
| Pen | PARTIAL | 实现存在，待独立桌面验收。 |
| Text | PARTIAL | 实现存在，待输入、撤销、输出验收。 |
| Mosaic | PARTIAL | 实现存在，待像素化效果与输出验收。 |
| Undo / Redo | PARTIAL | 编辑状态和按钮已接入；跨工具连续操作待验。 |
| Save PNG / Copy Image | PARTIAL | 输出路径已实现；需实际文件和目标 App 粘贴验证。 |
| OCR | MISSING | 未实现 Vision 识字、索引或搜索。 |
| Recording | MISSING | 未实现屏幕录制；macOS“屏幕与系统录制”权限仅供截图读取屏幕。 |

**Screenshot Module Complete：NO。** Quick Screenshot、区域/窗口捕获和 OCR 仍缺失。

## Unexpected Scope Expansion

此前用户明确要求参考 Deck 与 Pastory 的公开体验，特别保留 Pastory 风格的截图标注能力；因此 `6369859` 在 Stage 1 的主窗玻璃与贴边工作中提前加入了 Stage 3 的一部分。此顺序改变没有改变 Golden Master：八份 Clean-Room Handoff 文档和用户截图仍是需求依据。Deck、Pastory 仅为公开交互参考，**reference only**；本次未读取或复制两者源码，也未访问旧 PasteLoom/Clipth 源码。若将来引入 Pastory MIT 源码，需另行记录来源、许可证并保留 notice。

## Screen Recording Permission

未自动修改 TCC。系统设置中的开关虽显示已授权，当前构建的 `CGPreflightScreenCaptureAccess()` 仍返回拒绝，实际全屏截图被系统拦截。`3b4c286` 在设置页补充状态、重检和系统设置入口，但不代表截图验收通过。保持 `NEEDS MANUAL VALIDATION`，由用户核对运行中的准确 App 构建并重新测试，不绕过系统权限。

## Stable Core

继续保护 0.20 秒 Clipboard Monitor、SQLite v5 与既有历史、normalized image fingerprint 与数据库唯一约束、单实例 capture owner、Text/URL/Image/File/Multi-file 捕获、Copy Back 和 self-write suppression。审计没有改动这些代码或真实数据库。

## Pending Manual Tests

- 在正确签名及运行路径的构建中复核屏幕录制授权，再执行整屏截图、取消、Save PNG、Copy Image 和目标 App 粘贴；权限仍拒绝时记录系统状态与构建身份。
- 从历史图片逐项验收 Crop、Rectangle、Ellipse、Arrow、Line、Pen、Text、Mosaic，以及跨工具 Undo/Redo 与输出结果（AT30–32）。
- 验收主抽屉四向贴边、单屏及多显示器边界、圆角玻璃明暗可读性、纸卡及列表切换；用 200 条以上混合历史测试滚动、窄窗、首尾项目和预览（AT14–17、AT41）。
- 跨应用确认 Source App；重启后检查 Favorite、Pin、Tags；验证全文与标签搜索的实际结果及已有历史未丢失（AT01、AT10、AT12、AT13、AT19）。
- 检查设置页各可用开关即时生效、重启保留和未实现项不会误导用户；检查 PasteLoom Next 命名一致性。

## Verification Boundary

此前对当前代码执行的 Build 为 PASS，XCTest 为 **40 PASS / 0 FAIL**。本次文档审计未修改业务代码，未把自动测试等同于真实桌面验收。审计时真实数据库 schema v5，`PRAGMA quick_check=ok`，235 条历史可读；条数为动态快照。

Stage 1 tag 未创建；未 push。
