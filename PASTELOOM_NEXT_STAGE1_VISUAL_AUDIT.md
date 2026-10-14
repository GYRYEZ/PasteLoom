# PasteLoom Next Stage 1 Visual Audit

> 历史快照（2026-10-04）：以下桌面观察只对应 Stage 1B 当日构建。当前构建、测试与未完成的全项目桌面验收边界见 `PASTELOOM_NEXT_CURRENT_STATUS.md`。

日期：2026-10-04。依据 Clean-Room Golden Master、用户截图和固定路径 `AcceptanceBuild/PasteLoom Next.app` 的实际桌面观察。`MATCHED` 仅表示本次观察到的范围对齐；未实测的边界仍写 `PARTIAL`。

| 项目 | 实际观察 | 状态 |
|---|---|---|
| Main Drawer | 左侧约 520 pt 纵向圆角抽屉与玻璃背景可见；右侧、顶底、多屏和缩放边界未验 | PARTIAL |
| Header | PasteLoom Next 名称、捕获状态和设置入口清楚可见 | MATCHED |
| Search | 输入 URL 可实时筛选；搜索条件变化后列表回到顶部 | MATCHED |
| Search modes | 全文、标签状态明确；语义按钮禁用并说明后续实现 | MATCHED |
| Filter toolbar | 历史、收藏、类型/来源/日期筛选、多选、回收站、外观可见；组合筛选已命中 | PARTIAL |
| Text Card | 来源、时间、字数、截断正文、底部动作在列表中可见 | MATCHED |
| URL Card | 域名、完整 URL、来源与详情预览可见 | MATCHED |
| Image Card | Shottr 来源、像素与大小、按需缩略图、标注入口可见 | MATCHED |
| File Card | 文件名换行、类型、缩略图、路径摘要均留在卡片边界内 | MATCHED |
| Multi-file Card | 两个文件为一张卡，文件数和名称摘要可见；详情可逐项快速查看 | MATCHED |
| Source App | ChatGPT 与 Shottr 图标/名称可见；未知旧来源显示 Unknown | MATCHED |
| Footer Actions | 列表卡的预览、复制、置顶、收藏、标签、删除有实际动作；完整五类型写回未本轮重做 | PARTIAL |
| Hover | 450 ms 延迟和按需图片缩略图已实现；首次桌面出现弹层出屏，调整锚点后仍需人在完整屏幕确认位置、关闭和滚动 | PARTIAL |
| Selection | 多选入口可见；批量栏与键盘选择未做完整桌面验收 | PARTIAL |
| Typography | 标题、正文、元信息层级清楚；超长文件名与长文本没有横向溢出 | MATCHED |
| Spacing | 列表卡间距、内边距与圆角一致；未验证最窄尺寸和屏幕底边 | PARTIAL |
| Theme | 北欧白桦与黑曜石深邃切换后设计色实际改变；已恢复落日暖霞 | MATCHED |
| Light | 主抽屉及设置的浅色控件可见 | MATCHED |
| Dark | 主抽屉、纸卡与设置的深色变体可见 | MATCHED |
| System | 跟随系统设置已恢复；系统外观切换及 Quick Paste 跨窗口联动未实测 | PARTIAL |
| Settings | 七个一级入口、通用二级目录和主题/布局有效控件可见；所有规划页面与权限状态未逐项复核 | PARTIAL |

固定构建已真实启动，测试为 45 PASS / 0 FAIL；SQLite schema v5、`quick_check=ok`，历史从本轮开始的 243 条增长至末次检查的 248 条，没有清理数据。测试 URL 的收藏、置顶和两个临时标签经重启保留，随后已从 UI 恢复为原状态。未访问旧项目源码、资源、数据库或构建。
