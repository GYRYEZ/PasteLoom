# PasteLoom 当前状态

> **归档快照提示**：本文主体记录的是 2026-10-05 的验收快照，不代表当前 HEAD 或当前未提交工作区状态。公开仓库介绍请先阅读 `README.md`；如需新的验收结论，应重新构建、运行测试并检查数据库后更新本文件。

更新时间：2026-10-05（Asia/Shanghai）

## 代码与工作区

- 分支：`main`
- HEAD：`681fb14` — `fix: flush edge-to-edge docking, remove liquid glass transparency, resolve hover loop oscillations`
- 本次验收期间的工作区改动尚未提交，包含应用标识/图标资源、主抽屉卡片布局与品牌名、边缘悬停设置同步、关于页 Logo 和相关 Xcode 项目资源配置。
- 该改动没有编辑 Clipboard Monitor、SQLite schema、图片 fingerprint 去重、单实例 capture owner 或 Copy Back 实现。
- `AcceptanceBuild/` 被 `.gitignore` 排除。

## 本次自动验收

| 检查 | 结果 | 证据 |
|---|---|---|
| Xcode 全量测试 | PASS | `xcodebuild test`，86 passed / 0 failed / 0 skipped；`.xcresult` 汇总 `Passed` |
| SQLite 完整性 | PASS | `PRAGMA quick_check` 返回 `ok` |
| SQLite schema | v7 | `PRAGMA user_version` 返回 `7` |
| 历史保留 | PASS | 本次快照 `history_items` 291 条；运行中剪贴板捕获可使计数变化 |
| Bundle 身份 | PASS | `com.gyryez.pasteloom.next` |
| 应用名称 | PASS | `PasteLoom`（Display Name 与 Bundle Name） |
| 固定验收构建 | PASS | 已由当前测试构建产物复制至固定路径，ad hoc 签名验证通过并成功启动 |
| 桌面 smoke test | PASS（范围有限） | 主历史列表显示、卡片预览/置顶/收藏/标签/删除操作可访问；设置窗口和外观、四向停靠项可访问 |

验收应用位于本机忽略目录 `AcceptanceBuild/`；本状态文档不记录本机绝对路径。

此构建使用 ad hoc 签名，供本机验收，不是发行签名或公证产物。此次未更改 TCC / Accessibility / Screen Recording 权限。

## 桌面验收边界

本次没有执行完整的 Golden Master 逐项人工验收。以下需要后续人工或专门场景验证：

- 四边停靠下的真实屏幕边界、不同显示器、Dock 自动隐藏和边缘悬停。
- 快捷键冲突、实体键盘全局快捷键、Auto Paste 焦点恢复及 Accessibility 开关前后行为。
- 全屏/区域/窗口截图、标注 Save/Copy、Screen Recording 权限撤销与恢复。
- 长时间内存/CPU、快速重复捕获、完整内容类型 Copy Back 和高级数据操作的端到端场景。
- Dock/Finder 图标外观：`AppIcon.icns` 已打包进资源，但生成的 `Info.plist` 未显示 `CFBundleIconFile` 字段；本轮没有据此宣称系统 Dock 图标已验证。

因此，本次结论是“当前改动构建和自动化验证通过，桌面 smoke test 通过”，不等于全项目所有功能均完成桌面验收或可发布。

## 进度文档状态

- `PASTELOOM_NEXT_FEATURE_GAP_MATRIX.md` 已更新审计日期、当前测试数和数据库快照，并明确原有 DONE 是实现盘点，非完整人工验收结论。细分状态仍需在后续阶段按 Golden Master 逐项复核。
- `PASTELOOM_NEXT_IMPLEMENTATION_PLAN.md` 已更新为当前验证结果和桌面验收边界。
- `PASTELOOM_NEXT_STAGE1_REPORT.md` 与 `PASTELOOM_NEXT_STAGE1_VISUAL_AUDIT.md` 是 2026-10-04 的历史 Stage 1B 快照；其中旧测试数、schema 及历史计数只描述当时状态。
- 未创建新 tag，未 push。
- 未访问旧 PasteLoom / Clipth 源码、工程、资源、数据库或 Git 历史。
