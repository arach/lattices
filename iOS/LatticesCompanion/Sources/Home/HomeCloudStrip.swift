import SwiftUI

/// Thin strip showing aggregate cloud state — agents running, builds queued,
/// last deploy. One dense mono line; tap to expand into a short accordion of
/// running agents, queued builds, and last deploy detail.
///
/// Conceptually separate from the Mac fleet grid: cloud targets have slower
/// telemetry and different actions (agents/builds/deploys vs scenes/layouts),
/// so they live in their own thin strip and never mix into the Mac surface.
///
/// Size budget — collapsed: ~36pt. Expanded: ~100-120pt.
struct HomeCloudStrip: View {
    let cloud: HomeCloudStatus

    /// Per-row detail used in the expanded accordion. Tuples are (label, agoLabel).
    /// Defaults are empty until callers pass real cloud telemetry.
    var runningAgents: [(String, String)] = []
    var queuedBuilds: [(String, String)] = []
    var lastDeployDetail: String? = nil

    var onTap: (() -> Void)? = nil

    /// Initial expansion state. Defaults to collapsed; previews can pass
    /// `true` to render the expanded layout directly.
    var startsExpanded: Bool = false

    @State private var isExpanded: Bool

    init(
        cloud: HomeCloudStatus,
        runningAgents: [(String, String)] = [],
        queuedBuilds: [(String, String)] = [],
        lastDeployDetail: String? = nil,
        onTap: (() -> Void)? = nil,
        startsExpanded: Bool = false
    ) {
        self.cloud = cloud
        self.runningAgents = runningAgents
        self.queuedBuilds = queuedBuilds
        self.lastDeployDetail = lastDeployDetail
        self.onTap = onTap
        self.startsExpanded = startsExpanded
        self._isExpanded = State(initialValue: startsExpanded)
    }

    private var agentsTint: Color {
        cloud.agentsRunning > 0 ? LatsPalette.violet : LatsPalette.textFaint
    }

    private var buildsTint: Color {
        cloud.buildsQueued > 0 ? LatsPalette.amber : LatsPalette.textFaint
    }

    var body: some View {
        VStack(spacing: 0) {
            collapsedRow
            if isExpanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .top) {
            Rectangle().fill(LatsPalette.hairline2).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LatsPalette.hairline2).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
            onTap?()
        }
    }

    // MARK: - Collapsed row

    private var collapsedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LatsPalette.textDim)

            Text("CLOUD")
                .font(LatsFont.mono(9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(LatsPalette.textFaint)

            middot

            // Agents
            HStack(spacing: 5) {
                Circle()
                    .fill(agentsTint)
                    .frame(width: 5, height: 5)
                    .opacity(cloud.agentsRunning > 0 ? 1.0 : 0.5)
                Text("\(cloud.agentsRunning) agents")
                    .font(LatsFont.mono(10))
                    .foregroundStyle(agentsTint)
            }

            middot

            // Builds queued
            HStack(spacing: 5) {
                Circle()
                    .fill(buildsTint)
                    .frame(width: 5, height: 5)
                    .opacity(cloud.buildsQueued > 0 ? 1.0 : 0.5)
                Text("\(cloud.buildsQueued) builds queued")
                    .font(LatsFont.mono(10))
                    .foregroundStyle(buildsTint)
            }

            if let last = cloud.lastDeployAgo {
                middot
                Text("deploy \(last) ago")
                    .font(LatsFont.mono(10))
                    .foregroundStyle(LatsPalette.textDim)
            }

            Spacer(minLength: 0)

            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LatsPalette.textFaint)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private var middot: some View {
        Text("·")
            .font(LatsFont.mono(10))
            .foregroundStyle(LatsPalette.textFaint)
    }

    // MARK: - Expanded detail

    private var expandedDetail: some View {
        VStack(spacing: 0) {
            if !runningAgents.isEmpty {
                LatsHairlineDivider(color: LatsPalette.hairline)
                VStack(spacing: 0) {
                    ForEach(Array(runningAgents.enumerated()), id: \.offset) { idx, entry in
                        detailRow(
                            leadingDot: LatsPalette.violet,
                            label: entry.0,
                            trailing: "started \(entry.1)"
                        )
                        if idx < runningAgents.count - 1 {
                            LatsHairlineDivider(color: LatsPalette.hairline)
                        }
                    }
                }
            }

            if !queuedBuilds.isEmpty {
                LatsHairlineDivider(color: LatsPalette.hairline)
                ForEach(Array(queuedBuilds.enumerated()), id: \.offset) { _, entry in
                    detailRow(
                        leadingDot: LatsPalette.amber,
                        label: entry.0,
                        trailing: entry.1
                    )
                }
            }

            if let detail = lastDeployDetail {
                LatsHairlineDivider(color: LatsPalette.hairline)
                detailRow(
                    leadingDot: LatsPalette.textFaint,
                    label: "last deploy",
                    trailing: detail
                )
            }
        }
    }

    private func detailRow(leadingDot: Color, label: String, trailing: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(leadingDot).frame(width: 5, height: 5)
            Text(label)
                .font(LatsFont.mono(10))
                .foregroundStyle(LatsPalette.text)
            Spacer(minLength: 8)
            Text(trailing)
                .font(LatsFont.mono(10))
                .foregroundStyle(LatsPalette.textDim)
        }
        .padding(.horizontal, 14)
        .frame(height: 20)
    }
}

#Preview("Collapsed") {
    LatsBackground {
        VStack {
            Spacer()
            HomeCloudStrip(cloud: HomeMock.cloud)
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Expanded") {
    LatsBackground {
        VStack {
            Spacer()
            HomeCloudStrip(cloud: HomeMock.cloud, startsExpanded: true)
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
