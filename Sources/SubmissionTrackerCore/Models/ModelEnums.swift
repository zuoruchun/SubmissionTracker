import Foundation

// MARK: - Venue Type

/// 期刊 / 会议 / 预印本 / 其他
enum VenueType: String, Codable, CaseIterable, Identifiable, Sendable {
    case journal
    case conference
    case preprint
    case other

    var id: String { rawValue }

    /// 中英文显示名
    var displayNameZh: String {
        switch self {
        case .journal: return "期刊"
        case .conference: return "会议"
        case .preprint: return "预印本"
        case .other: return "其他"
        }
    }

    var displayNameEn: String {
        switch self {
        case .journal: return "Journal"
        case .conference: return "Conference"
        case .preprint: return "Preprint"
        case .other: return "Other"
        }
    }
}

// MARK: - Manuscript Status

/// 草稿 / 投稿中 / 外审 / 大修 / 小修 / 接收 / 拒稿 / 撤稿
enum ManuscriptStatus: String, Codable, CaseIterable, Identifiable, Sendable, Comparable {
    case draft
    case submitted
    case underReview
    case majorRevision
    case minorRevision
    case accept
    case reject
    case withdrawn

    var id: String { rawValue }

    /// 时间轴上的先后顺序（用于看板列序与进度展示）
    var order: Int {
        switch self {
        case .draft: return 0
        case .submitted: return 1
        case .underReview: return 2
        case .minorRevision: return 3
        case .majorRevision: return 4
        case .accept: return 5
        case .reject: return 6
        case .withdrawn: return 7
        }
    }

    /// 是否为"仍在推进中"的状态（用于菜单栏/统计）
    var isActive: Bool {
        switch self {
        case .draft, .submitted, .underReview, .majorRevision, .minorRevision:
            return true
        case .accept, .reject, .withdrawn:
            return false
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }

    var displayNameZh: String {
        switch self {
        case .draft: return "草稿"
        case .submitted: return "投稿中"
        case .underReview: return "外审中"
        case .majorRevision: return "大修"
        case .minorRevision: return "小修"
        case .accept: return "已接收"
        case .reject: return "已拒稿"
        case .withdrawn: return "已撤稿"
        }
    }

    var displayNameEn: String {
        switch self {
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .underReview: return "Under Review"
        case .majorRevision: return "Major Revision"
        case .minorRevision: return "Minor Revision"
        case .accept: return "Accepted"
        case .reject: return "Rejected"
        case .withdrawn: return "Withdrawn"
        }
    }
}

// MARK: - Attachment File Type

/// 手稿 / 审稿意见 / 回复信 / 补充材料
enum AttachmentFileType: String, Codable, CaseIterable, Identifiable, Sendable {
    case manuscript
    case reviewComments
    case responseLetter
    case supplementary

    var id: String { rawValue }

    var displayNameZh: String {
        switch self {
        case .manuscript: return "手稿"
        case .reviewComments: return "审稿意见"
        case .responseLetter: return "回复信"
        case .supplementary: return "补充材料"
        }
    }

    var displayNameEn: String {
        switch self {
        case .manuscript: return "Manuscript"
        case .reviewComments: return "Review Comments"
        case .responseLetter: return "Response Letter"
        case .supplementary: return "Supplementary"
        }
    }
}

// MARK: - Sync State

/// 本地已保存 / 待同步 / 同步中 / 已同步 / 同步失败
public enum SyncState: String, Codable, CaseIterable, Identifiable, Sendable {
    case local
    case pending
    case syncing
    case synced
    case failed

    public var id: String { rawValue }

    public var displayNameZh: String {
        switch self {
        case .local: return "本地已保存"
        case .pending: return "待同步"
        case .syncing: return "同步中"
        case .synced: return "已同步"
        case .failed: return "同步失败"
        }
    }
}

// MARK: - Revision Stage

/// 投稿/修改阶段轮次
public enum RevisionStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case r0 = "R0"
    case r1 = "R1"
    case r2 = "R2"
    case r3 = "R3"
    case accepted = "录用"
    case other = "其他"

    public var id: String { rawValue }

    public var displayNameZh: String {
        switch self {
        case .r0: return "初始投稿 (R0)"
        case .r1: return "第一轮修改 (R1)"
        case .r2: return "第二轮修改 (R2)"
        case .r3: return "第三轮修改 (R3)"
        case .accepted: return "最终录用/终稿"
        case .other: return "其他阶段"
        }
    }
}
