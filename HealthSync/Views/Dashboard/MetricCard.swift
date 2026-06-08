import SwiftUI

struct MetricCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let content: () -> Content

    init(title: String, icon: String, iconColor: Color, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            + Text(" \(unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LargeMetricView: View {
    let value: String
    let unit: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(unit)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyMetricView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
}
