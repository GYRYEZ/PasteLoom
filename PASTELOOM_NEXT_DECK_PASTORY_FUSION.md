# PasteLoom Next — Deck / Pastory 体验融合记录

日期：2026-10-04。独立实现；未读取、复制 Deck、Pastory 或旧 PasteLoom/Clipth 源码、资源、工程文件。公开项目只作为功能与外观参考。

## 本次落地

- 主历史窗口沿用现有四向贴边定位，改为透明圆角窗口。macOS 26 起叠加系统 SwiftUI Liquid Glass，低版本使用 AppKit visual effect 背景；保留纸质内容卡片、明暗主题与现有历史功能。
- 新增独立 ScreenCaptureKit 截图服务。入口位于主窗口工具栏，选取鼠标所在显示器并排除 PasteLoom Next 自身窗口。屏幕录制权限缺失时展示系统设置路径，不修改 TCC。
- 新增图片标注器，可从截图入口或既有图片历史打开。支持裁剪、矩形、椭圆、箭头、直线、画笔、文字、局部马赛克、七色、线宽、撤销与重做。
- 标注结果可保存为 PNG 或作为图片写回系统剪贴板。取消不写入剪贴板，也不改动历史原图。缩放预览与输出分离，输出保持源图像素尺寸；Retina 裁剪尺寸已有自动测试。
- 图片原始资源经持久化层读取，UI 不直接访问资产路径。截图与标注未修改现有 Clipboard Monitor、SQLite schema、图片指纹唯一索引或捕获 owner。

## 与两项目能力的关系

Deck 的边缘抽屉、圆角卡片和快速检索方向已进入主界面。Pastory 强调的截图标注工具已经具备核心编辑动作。现有 Next 的 Text、URL、Image、File、Multi-file、Quick Paste、主题与标签等功能继续使用当前实现。

仍未实现的能力按 `PASTELOOM_NEXT_IMPLEMENTATION_PLAN.md` 与 `PASTELOOM_NEXT_FEATURE_GAP_MATRIX.md` 分阶段处理，尤其是区域/窗口直接选择、快捷截图、截图 OCR、录屏、Deck 的规则/同步等。UI 入口不会被记为已通过端到端验收。

## 验证与限制

- Xcode 27.0、macOS 27 SDK：构建通过，40 个 XCTest 通过，包含截图渲染与裁剪像素测试。
- 当前桌面为 macOS 26.7，主窗口和旧图片标注器已实际打开；矩形拖动后撤销控件启用。截图按钮触发屏幕录制权限错误提示。
- 屏幕与系统录制权限当前被系统拒绝。因此直接截图、保存/复制标注结果的完整桌面链路仍需用户授权后验收。未修改 Accessibility 或 TCC。
- macOS 27 运行环境尚未实际验证。多显示器截图定位、复杂图片的性能及全部标注工具逐项桌面验收仍待测试。

## 项目参考与许可边界

- Deck：<https://github.com/yuzeguitarist/Deck>。其公开仓库对部分目录保留所有权利，并对 `deckclip/` 标注 AGPL-3.0-only；本项目没有复制实现或资源。
- Pastory：<https://github.com/nothingbutcici/pastory>。公开仓库标注 MIT；本项目同样没有复制实现或资源。
