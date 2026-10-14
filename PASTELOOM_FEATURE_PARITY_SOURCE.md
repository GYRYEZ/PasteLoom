# PasteLoom Feature Parity Source

**Exists**：YES = 用户界面直接可见或已有人工验收；PARTIAL = 入口/说明可见，但完整行为未在本次独立验证。不得把 PARTIAL 当作发布完成。**Persistence** 为用户应得到的持久结果；“待验”表示本次没有重启确认。Priority：P0 核心可用与数据安全，P1 主要工作流，P2 附加体验。

| Feature | Exists | User Entry | Behavior | Persistence | Permission | Priority |
| --- | --- | --- | --- | --- | --- | --- |
| Clipboard capture | YES | 监听开关；在其他应用复制 | 合规内容进入历史 | 历史保留；待验 | 通常无需辅助功能 | P0 |
| Text | YES | 复制文字 | 文本卡片显示来源、时间、字数、摘要 | 保留；待验 | 无特殊权限 | P0 |
| URL | YES | 复制网址 | 链接类型卡片，可净化追踪参数 | 保留；待验 | 无 | P1 |
| Image | YES | 复制图片 | 图片缩略图与尺寸/大小，提供预览和识字入口 | 保留；待验 | 无 | P0 |
| File | PARTIAL | 复制文件 | 文件类进入历史并可复用 | 待验 | 文件位置访问可能受系统限制 | P1 |
| Multi-file | PARTIAL | 同时复制多个文件 | 作为一组识别与复用 | 待验 | 同上 | P1 |
| Rich text | PARTIAL | 复制带格式内容 | 识别为富文本并尽量保持格式 | 待验 | 无 | P1 |
| Video | PARTIAL | 复制视频或视频类内容 | 视频类型与首帧/播放预览选项 | 待验 | 文件访问依来源 | P2 |
| History | YES | 主窗口、菜单栏、快速粘贴 | 时间序列浏览、滚动、类型元信息 | 保留；待验 | 无 | P0 |
| List / grid | YES | 更多菜单；面板设置 | 切换主历史或面板布局 | 设置保存待验 | 无 | P1 |
| Basic / full-text search | YES | 搜索栏“全文” | 关键词命中历史，清空恢复 | 查询状态可临时 | 无 | P0 |
| Semantic search | PARTIAL | 搜索栏“语义”、数据设置 | 按意思寻找相关词条；界面称本机完成 | 开关保存待验 | 无外发授权应被需要 | P1 |
| Tag search | YES | 搜索栏“标签” | 多标签任一/全部筛选 | 标签保存待验 | 无 | P1 |
| Type / source / date filtering | YES | 筛选按钮与搜索条件 | 缩小结果集 | 筛选状态待验 | 无 | P1 |
| Favorites | YES | 卡片星标、收藏筛选 | 加入或退出收藏集合 | 保存待验 | 无 | P1 |
| Pin | YES | 卡片图钉 | 置顶并受保留保护 | 保存待验 | 无 | P1 |
| Tags | YES | 卡片标签按钮 | 增删标签；用于筛选 | 保存待验 | 无 | P1 |
| Groups | YES | 更多菜单、快捷粘贴操作 | 新建、管理、归组、筛选 | 保存待验 | 无 | P1 |
| Snippets | YES | 更多菜单“新建片段” | 创建可重复使用的内容 | 保存待验 | 无 | P2 |
| Preview | YES | 卡片眼睛；面板悬停 | 展示长内容/图片 | 延迟设置保存待验 | 无 | P1 |
| Quick Paste | PARTIAL | 全局快捷键；快速面板 | 搜索、选择、粘贴回原应用 | 面板设置保存待验 | 自动粘贴需辅助功能 | P0 |
| Auto Paste | PARTIAL | 快速粘贴或双击卡片 | 自动向目标应用输入 | 相关设置待验 | 辅助功能 | P0 |
| Menu Bar | YES | 菜单栏图标 | 历史快捷入口，列表/网格及悬停预览 | 设置保存待验 | 无 | P1 |
| Edge Dock | YES | 停靠方位设置 | 左右竖向、顶底横向抽屉 | 设置保存待验 | 无 | P1 |
| Edge Hover | PARTIAL | 通用→窗口与行为 | 指针在边缘停留后呼出 | 开关/延迟保存待验 | 无 | P1 |
| Cursor Assistant | PARTIAL | 三击 Shift 设置 | 在光标附近呼出浮窗 | 开关保存待验 | 全局键监测行为待验 | P1 |
| Screenshot | PARTIAL | 快捷键与截图设置 | 区域或窗口捕获 | 输出保存待验 | 屏幕录制 | P1 |
| Screenshot Annotation | PARTIAL | 截图后画板 | 矩形、椭圆、箭头、直线、画笔、文字、马赛克、撤销、完成 | 结果可保存；待验 | 屏幕录制 | P1 |
| OCR | PARTIAL | 图片卡片识字；截图设置 | 从图片获取可检索文字 | 结果保留待验 | 无额外系统权限声明 | P1 |
| Text actions | PARTIAL | 历史操作/规则 | 纯文本复制、尾部空白清理、文本规则 | 设置保存待验 | 无 | P2 |
| Privacy / content protection | YES | 数据→内容保护 | 敏感片段遮蔽，外发原文需单独开启 | 设置保存待验 | 无 | P0 |
| Excluded apps / types | YES | 数据→捕获与过滤 | 不记录选中的来源或类型 | 设置保存待验 | 无 | P1 |
| Rules | PARTIAL | 脚本→规则 | 条件命中后执行用户配置的动作 | 规则保存待验 | 用户须理解动作风险 | P2 |
| Scripts | PARTIAL | 脚本页与手动运行 | 导入、运行、查看本次会话结果 | 规则保存；运行记录仅会话内 | 脚本执行需用户授权 | P2 |
| AI assistance | PARTIAL | 规则 AI 创建；AI 页 | 协助创建规则及连接客户端 | 配置保存待验 | 主动开启 | P2 |
| MCP integration | PARTIAL | AI→连接服务/可用能力 | 让获准客户端查询并整理本地历史 | 配置保存待验 | 主动开启；敏感原文另授权 | P2 |
| Widget | PARTIAL | 系统小组件 | 历史快捷展示 | 待验 | 系统小组件添加 | P2 |
| Sync | PARTIAL | 数据→同步 | 可选 iCloud、WebDAV、本地文件夹、S3；当前关闭 | 配置保存待验 | 用户主动连接目标 | P2 |
| Import / export | PARTIAL | 数据→导入与导出 | 备份、导入、受保护内容脱敏 | 导入数据持久；待验 | 文件读写 | P1 |
| Trash / restore | PARTIAL | 工具栏垃圾桶；数据设置 | 可恢复删除，当前期限 7 天 | 待验 | 无 | P1 |
| Retention | PARTIAL | 数据→存储与保留 | 分类期限、收藏/置顶保护 | 设置保存待验 | 无 | P1 |
| Statistics | PARTIAL | 更多→数据面板；数据设置 | 复制次数与统计视图 | 可关闭新统计；待验 | 无 | P2 |
| Themes / appearance | YES | 通用→外观与布局 | 六款纸张主题、明暗、强调色、语言 | 设置保存待验 | 无 | P1 |
| Shortcuts | YES | 快捷键设置 | 可编辑/清除/恢复默认的全局和面板键 | 保存待验 | 自动粘贴及截图分别需权限 | P1 |
| Settings / About | YES | 主工具栏设置 | 七个一级页，版本、反馈、许可 | 非动作设置保存待验 | 部分页引导系统授权 | P1 |

**未收录为已存在能力**：没有独立可验证的应用内 AI 聊天页；没有可验证的复杂工作流编排器。设置说明提到的其他系统表面不等于完成的产品入口。新项目不能据此表推断端到端验收通过。
