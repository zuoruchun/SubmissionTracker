import SwiftUI
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 预览载荷对象 (避免 Sheet 传递空 URL 导致白屏卡死)

struct FilePreviewPayload: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let subtitle: String

    var isPDF: Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    var isImage: Bool {
        ["png", "jpg", "jpeg", "webp", "tiff", "heic"].contains(url.pathExtension.lowercased())
    }

    var isText: Bool {
        ["tex", "txt", "md", "json", "csv", "bib", "log"].contains(url.pathExtension.lowercased())
    }
}

// MARK: - 原生 PDFKit Representable

#if os(macOS)
struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    @Binding var pdfViewRef: PDFView?

    init(url: URL, currentPage: Binding<Int>, totalPages: Binding<Int>, pdfViewRef: Binding<PDFView?> = .constant(nil)) {
        self.url = url
        self._currentPage = currentPage
        self._totalPages = totalPages
        self._pdfViewRef = pdfViewRef
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor.windowBackgroundColor

        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
        }

        context.coordinator.setup(pdfView: pdfView, parent: self)
        DispatchQueue.main.async {
            self.pdfViewRef = pdfView
        }
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            if let doc = PDFDocument(url: url) {
                nsView.document = doc
                context.coordinator.updatePageCount(doc: doc)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    class Coordinator: NSObject {
        var parent: PDFKitRepresentedView
        weak var pdfView: PDFView?

        init(_ parent: PDFKitRepresentedView) {
            self.parent = parent
        }

        func setup(pdfView: PDFView, parent: PDFKitRepresentedView) {
            self.pdfView = pdfView
            self.parent = parent
            if let doc = pdfView.document {
                updatePageCount(doc: doc)
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: pdfView
            )
        }

        func updatePageCount(doc: PDFDocument) {
            let count = doc.pageCount
            DispatchQueue.main.async {
                self.parent.totalPages = max(count, 1)
                self.parent.currentPage = 1
            }
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pv = notification.object as? PDFView,
                  let doc = pv.document,
                  let current = pv.currentPage else { return }
            let index = doc.index(for: current)
            DispatchQueue.main.async {
                self.parent.currentPage = index + 1
                self.parent.totalPages = max(doc.pageCount, 1)
            }
        }
    }
}
#else
struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    @Binding var pdfViewRef: PDFView?

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
            DispatchQueue.main.async {
                self.totalPages = max(doc.pageCount, 1)
                self.currentPage = 1
            }
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
#endif

// MARK: - PDF / 附件 查看器面板 (PDFViewerSheet)

struct PDFViewerSheet: View {
    let payload: FilePreviewPayload
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    #if os(macOS)
    @State private var pdfView: PDFView?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.title)
                        .font(AppTheme.serifTitle(15))
                        .lineLimit(1)
                    if !payload.subtitle.isEmpty {
                        Text(payload.subtitle)
                            .font(AppTheme.monoLabel(11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if payload.isPDF {
                    // 页码与缩放控制
                    HStack(spacing: 6) {
                        #if os(macOS)
                        Button {
                            pdfView?.goToPreviousPage(nil)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("上一页")
                        .disabled(currentPage <= 1)

                        Text("\(currentPage) / \(max(totalPages, 1))")
                            .font(AppTheme.monoLabel(12))
                            .frame(minWidth: 54)

                        Button {
                            pdfView?.goToNextPage(nil)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("下一页")
                        .disabled(currentPage >= totalPages)

                        Divider()
                            .frame(height: 16)

                        Button {
                            pdfView?.zoomIn(nil)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("放大")

                        Button {
                            pdfView?.zoomOut(nil)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("缩小")

                        Button {
                            pdfView?.autoScales = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("适合宽度/窗口")
                        #endif
                    }

                    Divider()
                        .frame(height: 16)
                }

                // 外部操作
                #if os(macOS)
                Button("Finder") {
                    FileService.reveal(url: payload.url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("在 Finder 中显示该文件")

                Button("外部打开") {
                    FileService.openExternally(url: payload.url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("使用系统默认应用打开")
                #endif

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))

            Divider()

            // 核心渲染区域
            Group {
                if payload.isPDF {
                    #if os(macOS)
                    PDFKitRepresentedView(
                        url: payload.url,
                        currentPage: $currentPage,
                        totalPages: $totalPages,
                        pdfViewRef: $pdfView
                    )
                    #else
                    PDFKitRepresentedView(
                        url: payload.url,
                        currentPage: $currentPage,
                        totalPages: $totalPages,
                        pdfViewRef: .constant(nil)
                    )
                    #endif
                } else if payload.isImage {
                    #if os(macOS)
                    if let nsImg = NSImage(contentsOf: payload.url) {
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .scaledToFit()
                                .padding()
                        }
                    } else {
                        fallbackView
                    }
                    #else
                    fallbackView
                    #endif
                } else if payload.isText {
                    if let str = try? String(contentsOf: payload.url, encoding: .utf8) {
                        ScrollView {
                            Text(str)
                                .font(AppTheme.monoLabel(12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .textSelection(.enabled)
                        }
                    } else {
                        fallbackView
                    }
                } else {
                    fallbackView
                }
            }
            .frame(minWidth: 780, idealWidth: 860, minHeight: 540, idealHeight: 640)
        }
        .frame(minWidth: 780, minHeight: 580)
    }

    private var fallbackView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(payload.url.lastPathComponent)
                .font(AppTheme.serifTitle(16))
            Text("该文件类型不支持内嵌预览，请使用外部默认应用打开。")
                .font(AppTheme.serifBody(12))
                .foregroundStyle(.secondary)
            Button("使用系统默认应用打开") {
                FileService.openExternally(url: payload.url)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
