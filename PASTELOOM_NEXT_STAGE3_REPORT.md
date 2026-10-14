# PasteLoom Next Stage 3 交付与验证报告

## 1. 概述与核心目标达成情况

本阶段聚焦于 **【Stage 3】媒体与图像智能增强（Media & Image Intelligence Enhancements）**，遵循 100% 净室开发（Clean-Room）与原生实现原则，在保持既有 53 个自动化测试全部通过的基础上，成功完成了区域截图、窗口截图、本地离线 OCR 识字、富文本格式保持与视频类型识别。

| 功能模块 | 目标要求 | 达成状态 | 实现技术与路径 |
|---|---|---|---|
| **选区截图 (Region Capture)** | 交互式半透明蒙版框选截图，支持拖拽选区与实时尺寸提示 | **DONE** | `InteractiveScreenshotOverlay.swift`，基于 AppKit 全屏覆盖面板与拖拽跟踪 |
| **窗口选择截图 (Window Capture)** | 点击选择当前屏幕上的独立窗口进行精确截取 | **DONE** | `CGWindowListCopyWindowInfo` + `CGWindowListCreateImage` 原生窗口捕获与坐标匹配 |
| **快捷截屏录入剪贴板** | 快捷键呼出截图，截取后自动推入历史记录及剪贴板 | **DONE** | 快捷键配置绑定、截图后自动触发剪贴板复制与持久化 |
| **本地纯离线 OCR 识字** | 基于 Apple 原生框架进行中英离线 OCR，提取文本并自动注入搜索索引 | **DONE** | `VisionOCRService.swift` (`VNRecognizeTextRequest`，支持 `zh-Hans`, `zh-Hant`, `en-US`，`.accurate` 模式) + SQLite `ocr_text` 索引 |
| **富文本格式保持** | 识别并保留 RTF 富文本格式，在粘贴与复制时恢复原生排版样式 | **DONE** | `NSPasteboard.PasteboardType.rtf`、`HistoryKind.richText`、SQLite `rtf_data BLOB` |
| **视频类型识别与元数据提取** | 识别 mp4/mov 等视频文件，提取时长与生成首帧预览缩略图 | **DONE** | `VideoMetadataExtractor.swift` (`AVURLAsset`, `AVAssetImageGenerator`)，格式化时长展示 |
| **截图编辑器集成** | 截图编辑预览窗口提供一键“识字 (OCR)”功能与文字快速复制 | **DONE** | `ScreenshotEditorView.swift` OCR 操作按钮与浮层展示卡片 |
| **设置与配置入口** | 增加“自动离线 OCR 识别”与“截图自动保存至历史记录”开关 | **DONE** | `SettingsView.swift` 媒体增强偏好设置绑定 |

---

## 2. 架构设计与改动明细

### 2.1 数据层与 SQLite 迁移 (Schema v6)
- **迁移逻辑**：在 `SQLiteHistoryRepository.swift` 中新增 `v6` 非破坏性迁移：
  - 新增 `ocr_text TEXT` 字段，存储 OCR 提取文本。
  - 新增 `rtf_data BLOB` 字段，存储 RTF 二进制排版格式数据。
  - 新增索引 `CREATE INDEX history_items_ocr ON history_items(ocr_text) WHERE ocr_text IS NOT NULL`。
  - `updateOCRText(_:for:)` 方法同时安全更新 `ocr_text` 与 `search_text`，实现 OCR 结果秒级无缝进入全文搜索。
- **现网数据安全**：验证了本地 live SQLite 数据库，无损从 v5 平滑过渡到 v6，现有 257 条真实历史记录完好无损，`quick_check` 返回 `ok`。

### 2.2 媒体与视觉智能服务
- **`VisionOCRService.swift`**：
  - 采用 Apple 原生 `Vision.framework` 的 `VNRecognizeTextRequest`。
  - 配置为高精度模式（`VNRequestTextRecognitionLevel.accurate`），开启语言矫正，优先适配简体中文（`zh-Hans`）、繁体中文（`zh-Hant`）和英文（`en-US`）。
  - 纯本地执行，无任何外部网络请求与第三方依赖。
- **`VideoMetadataExtractor.swift`**：
  - 采用 Apple 原生 `AVFoundation`。
  - 通过 `AVURLAsset` 异步或即时加载视频时长（duration），提供规范化时长格式转换（例如 `01:05`）。
  - 使用 `AVAssetImageGenerator` 在 `0.0s` 处截取第一帧高清缩略图并生成统一规范的 `ImageContent`。

### 2.3 剪贴板与格式分类扩展
- **`ClipboardClassifier.swift`**：
  - 扩充 `ClipboardSnapshot` 支持 `rtfData`。
  - 扩展文件分类：识别 `.mp4`, `.mov`, `.m4v`, `.mkv`, `.avi` 等常用视频后缀，优先划分为 `.video(FileReference)`。
  - 扩展富文本：当包含 RTF 数据且非网页 URL 时，优先归类为 `.richText(plain: String, rtfData: Data)`。
- **`ClipboardService.swift`**：
  - 写入系统剪贴板时同时写入 `.rtf` 与 `.string`，保证第三方文字处理器能恢复原格式排版。

### 2.4 UI 交互与视觉审计
- **主历史抽屉与卡片 (`HistoryView.swift`)**：
  - 筛选器新增“富文本”和“视频”类型标签。
  - 卡片 (`GridHistoryCard`, `PaperHistoryCard`) 展示富文本专属图标 `doc.richtext` 与视频专属播放标记 `video.fill`。
  - 详情抽屉展示 OCR 提取文本块，提供“一键复制识别文字”按钮与富文本即时预览。
- **快捷粘贴浮窗 (`QuickPasteView.swift`)**：
  - 支持多选与键盘批量复制富文本和视频卡片，徽标展示时长与多媒体类别。
- **菜单栏快速面板 (`MenuBarHistoryView.swift`)**：
  - 列表项同步区分富文本与视频，展示专用图标与标题摘要。

---

## 3. 测试验证与质量审计

### 3.1 自动化测试矩阵（XCTest）
- 执行命令：`xcodebuild test -project PasteLoomNext/PasteLoomNext.xcodeproj -scheme PasteLoomNext -destination 'platform=macOS'`
- 测试结果：**61 passed, 0 failed**（包含原 53 个基线测试 + 8 个 Stage 3 专属自动化测试）：
  - `Stage3Tests.testSchemaV6MigrationAndColumns`: 验证 v6 数据库迁移字段与数据读写。
  - `Stage3Tests.testRichTextInsertAndRetrieve`: 验证 RTF 二进制存储与关键词检索。
  - `Stage3Tests.testVideoInsertAndRetrieve`: 验证视频时长、首帧关联与条目检索。
  - `Stage3Tests.testVideoDurationFormatting`: 验证时间格式化逻辑。
  - `Stage3Tests.testOCRTextUpdateAndSearch`: 验证 OCR 提取文本更新及全文搜索命中。
  - `Stage3Tests.testClipboardClassifierRichTextAndVideo`: 验证剪贴板类型分类器对视频与富文本的判定。
  - `Stage3Tests.testVisionOCRServiceInvalidImageData`: 验证 OCR 输入异常处理。
  - `Stage3Tests.testVisionOCRServiceBlankImageRecognizesGracefully`: 验证空白图像 OCR 容错机制。

### 3.2 真实环境与本地数据库安全验证
- 目标路径：`~/Library/Application Support/com.gyryez.pasteloom.next/history.sqlite3`
- `PRAGMA quick_check`: `ok`
- `PRAGMA user_version`: `6`
- 历史记录计数：**257 条**（记录无任何丢失或破坏）

---

## 4. 交付制品

- **验收应用程序包**：`AcceptanceBuild/PasteLoom Next.app`（已使用 Release 配置构建并更新）
- **变更统计**：
  - 新增文件：
    - `PasteLoomNext/Media/VisionOCRService.swift`
    - `PasteLoomNext/Media/VideoMetadataExtractor.swift`
    - `PasteLoomNext/Screenshot/InteractiveScreenshotOverlay.swift`
    - `PasteLoomNextTests/Stage3Tests.swift`
  - 优化更新文件：
    - `PasteLoomNext/Domain/HistoryItem.swift`
    - `PasteLoomNext/Persistence/SQLiteHistoryRepository.swift`
    - `PasteLoomNext/Clipboard/ClipboardClassifier.swift`
    - `PasteLoomNext/Clipboard/ClipboardService.swift`
    - `PasteLoomNext/App/AppModel.swift`
    - `PasteLoomNext/QuickPaste/QuickPasteViewModel.swift`
    - `PasteLoomNext/QuickPaste/QuickPasteView.swift`
    - `PasteLoomNext/UI/MenuBarHistoryView.swift`
    - `PasteLoomNext/Screenshot/ScreenshotCaptureService.swift`
    - `PasteLoomNext/Screenshot/ScreenshotEditorView.swift`
    - `PasteLoomNext/UI/HistoryView.swift`
    - `PasteLoomNext/UI/SettingsView.swift`
    - `PasteLoomNextTests/ClipboardServiceTests.swift`
    - `PasteLoomNextTests/SQLiteHistoryRepositoryTests.swift`
    - `PasteLoomNext/PasteLoomNext.xcodeproj/project.pbxproj`
