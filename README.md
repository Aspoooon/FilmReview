# FilmReview

FilmReview 是一款本地 macOS 审片工具，用于逐帧定位、截图标注、记录修改意见和导出 PDF。Mac 通用版适用于运行 macOS 14 或更新系统的 Apple 芯片和 Intel Mac。

## 安装

从 [GitHub Releases](https://github.com/Aspoooon/FilmReview/releases/latest) 下载 `FilmReview-1.1-macOS-Universal.zip`。解压后，把 `FilmReview.app` 拖到「应用程序」，再打开。

发行包使用本地签名，尚未经过 Apple 公证。如果系统提示无法验证开发者，确认文件来源后，先尝试打开一次，再到「系统设置 → 隐私与安全性」选择「仍要打开」。[Apple 官方说明](https://support.apple.com/zh-cn/102445)

## 审片

1. 在项目库新建项目，导入第一支影片。
2. 同一项目的下一轮影片用「导入版本」加入。新版本从零条意见开始，顶部版本菜单可切回旧版本。重新进入项目时默认打开最后导入的版本。
3. 在画面上拖拽画框，松开即保存。也可点击右侧输入框，或按回车聚焦后写意见，再按回车保存。同一帧的快捷画框和文字合并在同一条意见中。
4. 时间线标记可点选定位。播放头经过标注附近时会显示文字和时间码，画框在对应帧显示。「标注工具」可使用箭头、文字和画笔，已有意见也可在右侧编辑。
5. 「导出 PDF」生成当前版本的 A4 竖版报告。首页直接展示意见，左边是截图和标注，右边是正文。长意见会自动续页。

## 保存与旧文件

项目库保存在 `~/Library/Application Support/FilmReview/Library/`，已提交的意见自动保存。源视频留在原位置。源视频移动后，可在应用内重新关联，已存截图仍可用于查看和导出。

- 「导入旧工程」将已有 `.filmreview` 作为副本导入。从项目库导入会创建项目，从项目内导入会加入当前项目。
- 如需交接单个版本，可用「文件 → 导出当前版本工程副本」。
- 备份整个项目库时，可在退出应用后复制 `Library` 文件夹。源视频需单独保管。

## 快捷键

| 快捷键 | 操作 |
| --- | --- |
| Space | 播放 / 暂停 |
| ← / → | 逐帧 |
| Return | 聚焦意见输入框 / 提交文字意见 |
| ⌘O | 导入送审版本 |
| ⇧⌘O | 导入旧审阅文件 |
| ⌘S | 立即保存当前版本 |
| ⇧⌘S | 导出当前版本工程副本 |
| ⌘N | 打开完整标注工具 |
| ⌘E | 导出 PDF |
| ⌘Z / ⇧⌘Z | 撤销 / 重做编辑中的标注 |

## 构建

运行 `./build.sh release`。构建产物在 `dist/FilmReview.app`。工程使用系统 SwiftUI、AppKit、AVFoundation、CoreGraphics 和 PDFKit。支持 AVFoundation 可解码的视频。可变帧率素材的显示帧号采用标称帧率，意见定位使用实际媒体时间戳。

如果沙箱限制生成调试符号，可在支持该选项的 Swift 工具链下运行 `FILMREVIEW_NO_DEBUG_INFO=1 ./build.sh release`。测试时可用环境变量 `FILMREVIEW_LIBRARY_PATH` 指向单独的项目库。

## 许可证

本项目采用 [MIT 许可证](LICENSE)。
