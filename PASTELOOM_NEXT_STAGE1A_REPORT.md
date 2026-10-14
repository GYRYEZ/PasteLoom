# PasteLoom Next Stage 1A — 核心功能收口

日期：2026-10-04。只扩展当前 Next 工程；未访问旧项目、Deck 或 Pastory 源码。未修改 Clipboard Monitor、图片去重、单实例保护、既有 SQLite schema 或真实历史。

## 交付与边界

| 项目 | 本轮结果 | 待验收范围 |
|---|---|---|
| Pin | 单项/批量置顶、取消、重启保留及排序原已具备；新增与 Favorite、软删除、恢复共存测试 | Golden Master 的保留期保护属于 Stage 4，尚未实现；AT19/35 待桌面验收 |
| Tags | 纸卡编辑多标签、增删与重启保留已有实现；新增跨记录组合测试 | AT12/19 待桌面验收 |
| Tag Search | 新增筛选中的逗号分隔多标签、任一 OR / 全部 AND、清除筛选；与全文查询取交集；设置页匹配模式保存至 UserDefaults | AT12 待桌面验收；标签模式原有输入按标签模糊匹配，筛选框按标签精确匹配 |
| Preview | 五类路由测试；多文件进入集合详情，可逐项 Quick Look；单文件可用时直接 Quick Look，缺失时安全进入详情 | Golden Master 的悬停预览属于 Stage 2，尚未实现；AT17/24 待桌面验收 |
| List Mode | LazyVStack 按需加载、悬停反馈、卡片动作及多选已存在；新增 220 条分页顺序与唯一 ID 测试 | AT15/18 的真实大量滚动、窗口尺寸与多选操作待验；主列表键盘导航未在当前规格中要求，快速粘贴导航保持原实现 |
| Settings Foundation | 外观、主题、捕获开关、监听间隔、快捷键、辅助功能状态、URL 净化与类型排除已有 backend；新增持久化的标签匹配选项。未实现页面维持 Planned 文案，不提供虚假开关 | 需在桌面逐项验收状态即时生效与重启保留 |

## 验证

- `xcodebuild test`：45 PASS，0 FAIL，包含原有 40 项。
- SQLite schema：v5，未迁移；真实数据库 `PRAGMA quick_check=ok`。
- 真实历史：开始 239 条，结束 239 条；未重建或清空数据库。计数是本轮实际采样，后台复制可能随后增加。
- 新增测试：Pin/收藏/删除恢复与重启；标签 OR/AND、全文组合和清除；五类预览及缺失文件路由；标签匹配设置持久化；220 条历史分页。

## 状态

Pin 的本轮操作链条可用，Golden Master 的保留期保护仍缺。Tags 的 Stage 1A 范围满足 UI、backend、persistence、test。Tag Search 与 List Mode 等待桌面验收；Preview 缺悬停行为。Stage 1 尚未整体完成，不创建 Stage 1 tag，也不 push。
