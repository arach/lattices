import SwiftUI

/// Cross-fleet activity feed. Compact rows: kind dot, kind label, title,
/// subtitle, target machine pill, ago label. Agent narration lands here too.
///
/// Size budget: ~220-280pt for ~5 rows.
struct HomeRecentTape: View {
    let entries: [HomeRecentEntry]
    var onReplay: ((HomeRecentEntry) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LatsSectionLabel(text: "Recent")
                Spacer()
                Text("last 24h · tap to replay")
                    .font(LatsFont.mono(9))
                    .tracking(0.5)
                    .foregroundStyle(LatsPalette.textFaint)
            }

            LatsCard(padding: 0) {
                if entries.isEmpty {
                    Text("no activity yet")
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textFaint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                            Button {
                                onReplay?(entry)
                            } label: {
                                HomeRecentRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .disabled(onReplay == nil)

                            if idx < entries.count - 1 {
                                LatsHairlineDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HomeRecentRow: View {
    let entry: HomeRecentEntry

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(entry.kind.dotColor)
                .frame(width: 6, height: 6)

            Text(entry.kind.label.uppercased())
                .font(LatsFont.mono(9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(LatsPalette.textFaint)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(LatsFont.ui(12, weight: .medium))
                    .foregroundStyle(LatsPalette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(LatsFont.mono(10))
                        .foregroundStyle(LatsPalette.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let target = entry.target {
                LatsBadge(text: target, tint: LatsPalette.textDim)
            }

            Text(entry.agoLabel)
                .font(LatsFont.mono(10))
                .foregroundStyle(LatsPalette.textFaint)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }
}

#Preview {
    LatsBackground {
        ScrollView {
            HomeRecentTape(entries: HomeMock.recent)
                .padding(14)
        }
    }
    .preferredColorScheme(.dark)
}
