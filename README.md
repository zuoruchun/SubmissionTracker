# 投稿追踪（SubmissionTracker）

管理论文投稿记录的 macOS 原生 App（SwiftUI + SwiftData），
支持 iOS/iPadOS 版本，两端通过 iCloud（CloudKit）自动同步。
视觉风格参考"研究者的私人笔记本"：米白纸张底色、衬线标题、
等宽字体日期与状态标签、克制的强调色。

## 当前进度（MVP）

- [x] 数据模型（SwiftData，CloudKit 安全）：Manuscript / StatusLogEntry / Attachment
- [x] 列表 + 详情双栏布局，按月分组（大号年月标题）
- [x] 状态时间线（可追加状态变更记录）
- [x] 文件关联：NSOpenPanel 选文件 + security-scoped bookmark 存储
- [x] 内嵌 QuickLook 预览（`.quickLookPreview`，macOS 11+ / iOS 14+）
- [x] "在 Finder 中显示"
- [x] 搜索（标题/期刊/标签/备注）+ 状态多选筛选 + 标签筛选 + 排序
- [x] 新增/编辑表单（含截止日期 → 本地通知提醒）
- [x] 看板视图（按状态分列，拖拽切换状态并自动记录）
- [x] 附件管理（手稿/审稿意见/回复信/补充材料）
- [x] 导出 CSV / Markdown 报告 / JSON 备份与恢复
- [x] 深色模式适配
- [x] 列表/看板视图切换（窗口大小记忆由 macOS frame autosave 提供）

待做（进阶）：日历/甘特视图、菜单栏入口、Widget、Spotlight、
统计仪表盘（Swift Charts）、多语言切换、审稿意见管理、合作者视图、
iOS 目标与真实 CloudKit 容器配置（见下）。

## 编译（命令行）

```
swift build          # macOS 可执行版本（开发验证用）
```

产物：`.build/debug/SubmissionTracker`

## 用 Xcode 构建正式 App（含 iCloud 同步）

1. 安装 xcodegen（如未装）：`brew install xcodegen`
2. 在本目录执行：`xcodegen generate`（依据 `project.yml`）
3. 打开生成的 `SubmissionTracker.xcodeproj`，在 Signing & Capabilities 中：
   - 选择你的 Team（自动签名）
   - 添加 **iCloud** capability → 勾选 **CloudKit**
   - 新建容器 `iCloud.com.zuoruchun.SubmissionTracker`
     （需在 Apple Developer 后台已登录同一 Apple ID）
4. 选择 macOS 目标 Run 即可。未配置容器前，App 会回退到**仅本地**存储，
   不影响使用；配置完成重启即自动启用云端同步。

> 注意：CloudKit 只同步元数据（含 bookmark 字节）。
> 文件本体依赖用户的 iCloud Drive 多设备可达性；
> 每台设备需要用本机可解析的 bookmark（`FileService.resolvedURL` 处理）。

## 项目结构

```
SubmissionTracker/
├── Package.swift                 # SPM：核心库 + macOS 可执行目标
├── project.yml                   # xcodegen 规格（Xcode 工程）
├── Entitlements/                 # 沙盒 + 文件访问 + CloudKit 容器
├── Sources/
│   ├── SubmissionTrackerCore/    # 跨平台共享代码
│   │   ├── Models/               # SwiftData 模型与枚举（CloudKit 安全）
│   │   ├── Services/             # FileService / NotificationService / ExportService / SyncConfig
│   │   ├── ViewModels/           # FilterState（搜索/筛选/排序）
│   │   ├── Views/                # 列表/详情/时间线/看板/表单
│   │   └── Theme/                # "私人笔记本"视觉主题
│   └── SubmissionTrackerApp/     # macOS App 入口（@main）
└── _codex_sessions/              # 会话记录
```
