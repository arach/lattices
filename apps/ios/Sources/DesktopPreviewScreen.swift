import DeckKit
import SwiftUI
import UIKit

/// A read-only, couch-friendly view of the paired Mac's current display.
///
/// Frames are intentionally pulled one at a time. The next request starts only
/// after the current JPEG has arrived and decoded, so a weak Wi-Fi connection
/// cannot build up a stale queue of screen captures.
struct DesktopPreviewScreen: View {
    @ObservedObject var store: DeckStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var image: UIImage?
    @State private var frame: DeckDesktopPreviewFrame?
    @State private var requestedDisplayIndex: Int?
    @State private var isAutoRefreshing = true
    @State private var isFetching = false
    @State private var errorMessage: String?
    @State private var refreshGeneration = 0

    private let refreshInterval = Duration.seconds(2)

    private var previewTaskID: PreviewTaskID {
        PreviewTaskID(
            displayIndex: requestedDisplayIndex,
            isAutoRefreshing: isAutoRefreshing,
            refreshGeneration: refreshGeneration,
            isSceneActive: scenePhase == .active
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            previewStage
            footer
        }
        .background(DeckTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task(id: previewTaskID) {
            await runPreviewLoop()
        }
    }

    private var header: some View {
        HStack(spacing: DeckTheme.Space.x12) {
            PreviewIconButton(
                systemName: "xmark",
                label: "Close Desktop Preview",
                action: { dismiss() }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Desktop Preview")
                    .font(DeckTheme.title())
                    .foregroundStyle(DeckTheme.text)
                Text(store.connectionLabel)
                    .font(DeckTheme.caption())
                    .foregroundStyle(DeckTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let frame, frame.displays.count > 1 {
                displayPicker(frame.displays)
            }

            PreviewIconButton(
                systemName: isAutoRefreshing ? "pause.fill" : "play.fill",
                label: isAutoRefreshing ? "Pause automatic refresh" : "Resume automatic refresh",
                action: { isAutoRefreshing.toggle() }
            )

            PreviewIconButton(
                systemName: "arrow.clockwise",
                label: "Refresh now",
                isBusy: isFetching,
                action: { refreshGeneration += 1 }
            )
        }
        .padding(.horizontal, DeckTheme.Space.margin)
        .padding(.vertical, DeckTheme.Space.x12)
        .background(DeckTheme.well)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DeckTheme.hairline)
                .frame(height: 1)
        }
    }

    private var previewStage: some View {
        ZStack {
            Color.black

            if let image {
                DesktopPreviewImageView(image: image)
                    .accessibilityLabel("Current screen on \(store.connectionLabel)")
                    .accessibilityHint("Pinch or double-tap to zoom, then drag to inspect the screen.")

                if let errorMessage {
                    staleFrameBanner(errorMessage)
                        .padding(DeckTheme.Space.margin)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            } else if let errorMessage {
                initialErrorState(errorMessage)
            } else {
                loadingState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var loadingState: some View {
        VStack(spacing: DeckTheme.Space.x16) {
            ProgressView()
                .controlSize(.large)
                .tint(DeckTheme.accent)
            Text("Reading \(store.connectionLabel)'s screen…")
                .font(DeckTheme.body(.medium))
                .foregroundStyle(DeckTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading \(store.connectionLabel)'s screen")
    }

    private func initialErrorState(_ message: String) -> some View {
        let presentation = errorPresentation(for: message)
        return VStack(spacing: DeckTheme.Space.x16) {
            Image(systemName: presentation.icon)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(DeckTheme.error)

            VStack(spacing: DeckTheme.Space.x8) {
                Text(presentation.title)
                    .font(DeckTheme.title())
                    .foregroundStyle(DeckTheme.text)
                    .multilineTextAlignment(.center)
                Text(presentation.detail)
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button {
                refreshGeneration += 1
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(DeckTheme.body(.semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, DeckTheme.Space.x16)
                    .frame(minHeight: 44)
                    .background(DeckTheme.accent, in: RoundedRectangle(cornerRadius: DeckTheme.radiusCard))
            }
            .buttonStyle(.plain)
        }
        .padding(DeckTheme.Space.x32)
        .frame(maxWidth: 480)
    }

    private func staleFrameBanner(_ message: String) -> some View {
        let presentation = errorPresentation(for: message)
        return HStack(spacing: DeckTheme.Space.x12) {
            Image(systemName: presentation.icon)
                .foregroundStyle(DeckTheme.error)
            Text(presentation.detail)
                .font(DeckTheme.secondary(.medium))
                .foregroundStyle(DeckTheme.text)
                .lineLimit(2)
            Spacer(minLength: DeckTheme.Space.x8)
            Button("Retry") { refreshGeneration += 1 }
                .font(DeckTheme.secondary(.semibold))
                .foregroundStyle(DeckTheme.accent)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, DeckTheme.Space.x16)
        .padding(.trailing, DeckTheme.Space.x8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DeckTheme.radiusWell))
        .overlay {
            RoundedRectangle(cornerRadius: DeckTheme.radiusWell)
                .stroke(DeckTheme.error.opacity(0.35), lineWidth: 1)
        }
        .frame(maxWidth: 680)
    }

    private var footer: some View {
        HStack(spacing: DeckTheme.Space.x12) {
            HStack(spacing: DeckTheme.Space.x8) {
                Circle()
                    .fill(errorMessage == nil ? DeckTheme.accent : DeckTheme.error)
                    .frame(width: 7, height: 7)

                if let frame {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("Captured \(Text(frame.capturedAt, style: .relative))")
                    }
                    .font(DeckTheme.caption(.medium))
                    .foregroundStyle(DeckTheme.textSecondary)

                    Text("\(frame.pixelWidth) × \(frame.pixelHeight)")
                        .font(DeckTheme.caption())
                        .foregroundStyle(DeckTheme.textTertiary)
                } else {
                    Text(isFetching ? "Connecting…" : "Waiting for screen")
                        .font(DeckTheme.caption(.medium))
                        .foregroundStyle(DeckTheme.textSecondary)
                }
            }

            Spacer()

            Label(
                isAutoRefreshing ? "Refreshes every 2 seconds" : "Refresh paused",
                systemImage: isAutoRefreshing ? "arrow.triangle.2.circlepath" : "pause.circle"
            )
            .font(DeckTheme.caption())
            .foregroundStyle(DeckTheme.textTertiary)

            Label("Encrypted on your local connection", systemImage: "lock.fill")
                .font(DeckTheme.caption())
                .foregroundStyle(DeckTheme.textTertiary)
        }
        .padding(.horizontal, DeckTheme.Space.margin)
        .frame(minHeight: 44)
        .background(DeckTheme.well)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DeckTheme.hairline)
                .frame(height: 1)
        }
    }

    private func displayPicker(_ displays: [DeckDesktopPreviewDisplay]) -> some View {
        Menu {
            ForEach(displays) { display in
                Button {
                    requestedDisplayIndex = display.displayIndex
                } label: {
                    Label(display.name, systemImage: display.displayIndex == currentDisplayIndex ? "checkmark" : "display")
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "display.2")
                Text(currentDisplayName(in: displays))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(DeckTheme.secondary(.medium))
            .foregroundStyle(DeckTheme.textSecondary)
            .padding(.horizontal, DeckTheme.Space.x12)
            .frame(minHeight: 44)
            .background(DeckTheme.control, in: RoundedRectangle(cornerRadius: DeckTheme.radiusCard))
        }
        .accessibilityLabel("Choose Mac display")
    }

    private var currentDisplayIndex: Int? {
        requestedDisplayIndex ?? frame?.displayIndex
    }

    private func currentDisplayName(in displays: [DeckDesktopPreviewDisplay]) -> String {
        displays.first(where: { $0.displayIndex == currentDisplayIndex })?.name ?? "Display"
    }

    private func runPreviewLoop() async {
        guard scenePhase == .active else { return }

        while !Task.isCancelled {
            let succeeded = await fetchFrame()
            guard succeeded, isAutoRefreshing, !Task.isCancelled else { return }
            try? await Task.sleep(for: refreshInterval)
        }
    }

    private func fetchFrame() async -> Bool {
        isFetching = true
        defer { isFetching = false }

        do {
            let nextFrame = try await store.desktopPreview(displayIndex: requestedDisplayIndex)
            try Task.checkCancellation()
            guard
                let jpeg = Data(base64Encoded: nextFrame.jpegBase64),
                let nextImage = UIImage(data: jpeg)
            else {
                throw DesktopPreviewDecodeError.invalidJPEG
            }

            frame = nextFrame
            image = nextImage
            errorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func errorPresentation(for message: String) -> PreviewErrorPresentation {
        let lowercased = message.lowercased()
        if lowercased.contains("screen.preview") || lowercased.contains("pair again") {
            return PreviewErrorPresentation(
                icon: "lock.trianglebadge.exclamationmark",
                title: "Screen Preview needs approval",
                detail: "Forget and add this Mac again to approve Screen Preview for this iPad."
            )
        }
        if lowercased.contains("screen recording") {
            return PreviewErrorPresentation(
                icon: "rectangle.inset.filled.and.person.filled",
                title: "Allow Screen Recording on the Mac",
                detail: message
            )
        }
        return PreviewErrorPresentation(
            icon: "wifi.exclamationmark",
            title: "Can't refresh the Mac screen",
            detail: message
        )
    }
}

private struct PreviewTaskID: Hashable {
    let displayIndex: Int?
    let isAutoRefreshing: Bool
    let refreshGeneration: Int
    let isSceneActive: Bool
}

private struct PreviewErrorPresentation {
    let icon: String
    let title: String
    let detail: String
}

private enum DesktopPreviewDecodeError: LocalizedError {
    case invalidJPEG

    var errorDescription: String? {
        "The Mac returned a screen image that this iPad could not display."
    }
}

private struct PreviewIconButton: View {
    let systemName: String
    let label: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: systemName)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DeckTheme.textSecondary)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(DeckTheme.textSecondary)
            .frame(width: 44, height: 44)
            .background(DeckTheme.control, in: RoundedRectangle(cornerRadius: DeckTheme.radiusCard))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// UIScrollView supplies native pinch, pan, and double-tap zoom behavior while
/// SwiftUI owns the surrounding controls and state.
private struct DesktopPreviewImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = context.coordinator.imageView
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let sizeChanged = context.coordinator.imageView.image?.size != image.size
        context.coordinator.imageView.image = image
        if sizeChanged {
            scrollView.setZoomScale(1, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let location = gesture.location(in: imageView)
            let targetScale = min(2, scrollView.maximumZoomScale)
            let width = scrollView.bounds.width / targetScale
            let height = scrollView.bounds.height / targetScale
            let rect = CGRect(
                x: location.x - width / 2,
                y: location.y - height / 2,
                width: width,
                height: height
            )
            scrollView.zoom(to: rect, animated: true)
        }
    }
}
