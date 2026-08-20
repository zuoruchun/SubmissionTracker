import SwiftUI

/// 视觉主题："研究者的私人笔记本"
/// 米白纸张底色、衬线标题、等宽字体做日期/状态标签、克制强调色。
enum AppTheme {

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

    /// 藏青：投稿中 / 外审，主强调色
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
        case .submitted, .underReview: return navy
        case .majorRevision, .minorRevision: return ochre
        case .accept: return moss
        case .reject, .withdrawn: return brick
        }
    }

    static func statusIcon(_ status: ManuscriptStatus) -> String {
        switch status {
        case .draft: return "pencil.line"
        case .submitted: return "paperplane"
        case .underReview: return "hourglass"
        case .majorRevision: return "pencil.and.outline"
        case .minorRevision: return "pencil"
        case .accept: return "checkmark.seal"
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

    /// 衬线标题
    static func serifTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// 衬线正文
    static func serifBody(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// 等宽字体：日期 / 状态标签
    static func monoLabel(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    /// 状态徽章
    static func statusBadge(_ status: ManuscriptStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon(status))
                .font(.system(size: 9, weight: .semibold))
            Text(status.displayNameZh)
                .font(monoLabel(11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor(status).opacity(0.15))
        .foregroundStyle(statusColor(status))
        .clipShape(Capsule())
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
