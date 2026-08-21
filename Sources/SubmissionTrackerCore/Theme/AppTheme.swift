import SwiftUI

/// 视觉主题："研究者的私人笔记本"
/// 米白纸张底色、衬线标题、等宽字体做日期/状态标签、克制强调色。
@MainActor
public enum AppTheme {

    // MARK: - 底色

    /// 米白纸张底色（浅色模式）
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.91)
    /// 略深的纸张色（分组卡片底，浅色模式）
    static let paperDark = Color(red: 0.93, green: 0.91, blue: 0.86)
    /// 深色模式下的"纸张"
    static let paperDarkMode = Color(red: 0.11, green: 0.11, blue: 0.12)
    /// 深色模式下的卡片底
    static let cardDarkMode = Color(red: 0.15, green: 0.15, blue: 0.16)

    // MARK: - 强调色（按状态）

    /// 藏青：投稿、编辑部处理、外审和修回稿提交，主强调色
    static let navy = Color(red: 0.16, green: 0.24, blue: 0.38)
    static let accent = navy
    /// 赭石：修订中
    static let ochre = Color(red: 0.62, green: 0.42, blue: 0.18)
    /// 苔绿：已接收
    static let moss = Color(red: 0.33, green: 0.44, blue: 0.30)
    /// 砖红：拒稿 / 撤稿
    static let brick = Color(red: 0.55, green: 0.26, blue: 0.22)
    /// 中性灰褐：草稿
    static let taupe = Color(red: 0.45, green: 0.42, blue: 0.38)

    static func statusColor(_ status: ManuscriptStatus) -> Color {
        switch status {
        case .draft: return taupe
        case .submitted, .editorialReview, .underReview, .revisionSubmitted: return navy
        case .majorRevision, .minorRevision: return ochre
        case .accept, .published: return moss
        case .reject, .withdrawn: return brick
        }
    }

    static func statusIcon(_ status: ManuscriptStatus) -> String {
        switch status {
        case .draft: return "pencil.line"
        case .submitted: return "paperplane"
        case .editorialReview: return "person.crop.circle.badge.clock"
        case .underReview: return "hourglass"
        case .majorRevision: return "pencil.and.outline"
        case .minorRevision: return "pencil"
        case .revisionSubmitted: return "paperplane.circle"
        case .accept: return "checkmark.seal"
        case .published: return "books.vertical"
        case .reject: return "xmark.seal"
        case .withdrawn: return "archivebox"
        }
    }

    static func venueIcon(_ type: VenueType) -> String {
        switch type {
        case .journal: return "book.closed"
        case .conference: return "building.columns"
        case .preprint: return "doc.text"
        case .other: return "square.grid.2x2"
        }
    }

    // MARK: - 字体

    public static var fontScale: CGFloat {
        FontSizeManager.shared.scale
    }

    /// 衬线标题
    public static func serifTitle(_ size: CGFloat) -> Font {
        .system(size: size * fontScale, weight: .semibold, design: .serif)
    }

    /// 衬线正文
    public static func serifBody(_ size: CGFloat = 14) -> Font {
        .system(size: size * fontScale, weight: .regular, design: .serif)
    }

    /// 等宽字体：日期 / 状态标签
    public static func monoLabel(_ size: CGFloat = 12) -> Font {
        .system(size: size * fontScale, weight: .medium, design: .monospaced)
    }

    /// 状态徽章
    static func statusBadge(_ status: ManuscriptStatus) -> some View {
        HStack(spacing: 4 * fontScale) {
            Image(systemName: statusIcon(status))
                .font(.system(size: 9 * fontScale, weight: .semibold))
            Text(status.displayNameZh)
                .font(monoLabel(11))
        }
        .padding(.horizontal, 8 * fontScale)
        .padding(.vertical, 3 * fontScale)
        .background(statusColor(status).opacity(0.15))
        .foregroundStyle(statusColor(status))
        .clipShape(Capsule())
    }
}

// MARK: - 字体缩放档位与响应式管理器

public enum FontSizeScaleLevel: String, CaseIterable, Identifiable, Sendable {
    case compact = "compact"       // 85%
    case standard = "standard"     // 100%
    case medium = "medium"         // 115%
    case large = "large"           // 130%
    case extraLarge = "extraLarge" // 145%

    public var id: String { rawValue }

    public var displayNameZh: String {
        switch self {
        case .compact: return "小字 (85%)"
        case .standard: return "标准 (100%)"
        case .medium: return "偏大 (115%)"
        case .large: return "大字 (130%)"
        case .extraLarge: return "特大 (145%)"
        }
    }

    public var scaleFactor: CGFloat {
        switch self {
        case .compact: return 0.85
        case .standard: return 1.0
        case .medium: return 1.15
        case .large: return 1.30
        case .extraLarge: return 1.45
        }
    }

    public var previous: FontSizeScaleLevel {
        switch self {
        case .compact: return .compact
        case .standard: return .compact
        case .medium: return .standard
        case .large: return .medium
        case .extraLarge: return .large
        }
    }

    public var next: FontSizeScaleLevel {
        switch self {
        case .compact: return .standard
        case .standard: return .medium
        case .medium: return .large
        case .large: return .extraLarge
        case .extraLarge: return .extraLarge
        }
    }
}

/// 全局字体缩放响应式管理器
@MainActor
public final class FontSizeManager: ObservableObject {
    public static let shared = FontSizeManager()

    @Published public var currentLevel: FontSizeScaleLevel = .standard {
        didSet {
            UserDefaults.standard.set(currentLevel.rawValue, forKey: "STFontSizeScaleLevel")
        }
    }

    public init() {
        let savedRaw = UserDefaults.standard.string(forKey: "STFontSizeScaleLevel") ?? ""
        self.currentLevel = FontSizeScaleLevel(rawValue: savedRaw) ?? .standard
    }

    public var scale: CGFloat {
        currentLevel.scaleFactor
    }

    public func zoomIn() {
        currentLevel = currentLevel.next
    }

    public func zoomOut() {
        currentLevel = currentLevel.previous
    }

    public func reset() {
        currentLevel = .standard
    }
}

/// 在视图中使用的主题背景：自动适配深/浅色模式。
struct ThemedBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                (colorScheme == .dark ? AppTheme.paperDarkMode : AppTheme.paper)
                    .ignoresSafeArea()
            }
    }
}

extension View {
    /// 应用"纸张"主题背景
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }

    /// 应用"卡片"底色
    func themedCard() -> some View {
        modifier(ThemedCard())
    }
}

struct ThemedCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? AppTheme.cardDarkMode : AppTheme.paperDark)
                    .opacity(0.5)
            )
    }
}
