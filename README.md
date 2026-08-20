# 投稿追踪 (SubmissionTracker)

专为高校学者、科研人员与研究生打造的学术论文全生命周期管理 macOS 原生应用。基于 **SwiftUI** 与 **SwiftData** 构建，采用“**研究者的私人笔记本**”视觉设计美学（米白纸张底色、典雅衬线标题、等宽状态标签与克制强调色）。

---

## 🌟 核心功能

- 📅 **全生命周期状态时间线**
  - 精准记录从初次投稿、编辑部处理、送外审、等待修回（大修/小修）、修改稿提交（R1/R2/R3…）到正式录用的完整链路。
- 🌐 **全局动态时间流 (Global Timeline)**
  - 汇总所有论文的全局事件演进，纵向连线展示；支持鼠标悬浮论文标题动态下划线高亮，点击直达论文详情并支持一键返回。
- 📄 **原生 PDFKit 预览与版本文件关联**
  - 手稿、修改稿、审稿意见与回复信直接挂载至对应状态节点，状态右侧一键秒开 PDF 查看器。
- 🥳 **论文录用专属祝贺横幅**
  - 论文被期刊正式接收（Accepted）后自动浮现专属祝贺横幅；内置 16 款不同风格文案，采用确定性伪随机算法为每篇论文分配稳定且专属的庆祝文案。
- ☁️ **坚果云 / WebDAV 云同步**
  - 支持坚果云及任意标准 WebDAV 服务端双向自动同步；元数据与文件本地托管，支持导出 CSV / Markdown 报告 / JSON 备份。
- 🔒 **Local-First 本地优先与隐私安全**
  - 数据完全存储于本地，零外部数据上报，代码不嵌入任何个人隐私信息。

---

## 🚀 快速安装与运行

### 方式一：直接下载 Release（推荐）

1. 在仓库的 **[Releases](https://github.com/zuoruchun/SubmissionTracker/releases)** 页面下载最新的 `SubmissionTracker-macOS.zip`；
2. 解压后将 `SubmissionTracker.app` 拖入系统的 **应用程序 (Applications)** 文件夹即可打开使用。

### 方式二：源码编译 Release

确保系统已安装 Xcode 15+ 或 Swift 5.10+：

```bash
git clone https://github.com/zuoruchun/SubmissionTracker.git
cd SubmissionTracker
swift build -c release
```

---

## 🛠 技术栈与系统要求

- **操作系统**：macOS 14.0 (Sonoma) 及以上版本
- **核心框架**：SwiftUI, SwiftData, PDFKit, UniformTypeIdentifiers, AppKit
- **架构设计**：Local-First 架构，多端适配准备

---

## 📄 开源许可

本项目基于 [MIT License](LICENSE) 开源。
