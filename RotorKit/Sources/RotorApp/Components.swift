import SwiftUI

/// 卡片容器
struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline).foregroundStyle(.secondary) }
            content
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06)))
    }
}

/// 大数字仪表块（少字多图）
struct StatTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var systemImage: String = "gauge"
    var tint: Color = .accentColor
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: systemImage)
                .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint)
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 实时页单行使用的小型数据块。
struct CompactStatTile: View {
    let label: String
    let value: String
    var unit: String = ""
    var systemImage: String = "gauge"
    var tint: Color = .accentColor
    var tooltip: String? = nil

    @ViewBuilder
    var body: some View {
        if let tooltip, !tooltip.isEmpty {
            tile.help(tooltip)
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 状态指示点
struct StatusDot: View {
    let ok: Bool
    var body: some View {
        Circle().fill(ok ? Color.green : Color.secondary)
            .frame(width: 9, height: 9)
            .shadow(color: ok ? .green.opacity(0.6) : .clear, radius: 4)
    }
}

extension Double {
    func f(_ digits: Int = 1) -> String { String(format: "%.\(digits)f", self) }
}
