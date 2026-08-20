import SwiftUI
import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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

    public func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor.windowBackgroundColor

        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
            DispatchQueue.main.async {
                self.totalPages = doc.pageCount
                self.currentPage = 1
                self.pdfViewRef = pdfView
            }
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    public func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            if let doc = PDFDocument(url: url) {
                nsView.document = doc
                DispatchQueue.main.async {
                    self.totalPages = doc.pageCount
                    self.currentPage = 1
                }
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject {
        var parent: PDFKitRepresentedView
        init(_ parent: PDFKitRepresentedView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let doc = pdfView.document,
                  let current = pdfView.currentPage else { return }
            let index = doc.index(for: current)
            DispatchQueue.main.async {
                self.parent.currentPage = index + 1
                self.parent.totalPages = doc.pageCount
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

    public func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
            DispatchQueue.main.async {
                self.totalPages = doc.pageCount
                self.currentPage = 1
            }
        }
        return pdfView
    }

    public func updateUIView(_ uiView: PDFView, context: Context) {}
}
#endif

// MARK: - PDF 查看器面板 (PDFViewerSheet)

struct PDFViewerSheet: View {
    let fileURL: URL
    let title: String
    let subtitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    #if os(macOS)
    @State private var pdfView: PDFView?
    #endif

    init(fileURL: URL, title: String, subtitle: String = "") {
        self.fileURL = fileURL
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.serifTitle(15))
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppTheme.monoLabel(11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

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

                // 外部操作
                #if os(macOS)
                Button("Finder") {
                    FileService.reveal(url: fileURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("在 Finder 中显示该文件")

                Button("外部打开") {
                    FileService.openExternally(url: fileURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("使用系统默认应用（如 Preview）打开")
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

            // PDF 核心渲染区域
            #if os(macOS)
            PDFKitRepresentedView(
                url: fileURL,
                currentPage: $currentPage,
                totalPages: $totalPages,
                pdfViewRef: $pdfView
            )
            .frame(minWidth: 700, minHeight: 520)
            #else
            PDFKitRepresentedView(
                url: fileURL,
                currentPage: $currentPage,
                totalPages: $totalPages,
                pdfViewRef: .constant(nil)
            )
            .frame(minWidth: 320, minHeight: 480)
            #endif
        }
        .frame(minWidth: 760, minHeight: 580)
    }
}
