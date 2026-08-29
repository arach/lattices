import AppKit
import SwiftUI

struct ActionSessionThumbnailView: View {
    let session: ActionSessionSummary
    /// Fixed width. Pass `nil` to fill the parent width.
    var width: CGFloat? = 150
    var height: CGFloat = 94
    var showCaption: Bool = true
    var showDuration: Bool = true
    var showNoteCount: Bool = false
    var cornerRadius: CGFloat = 10
    var showBorder: Bool = true

    @State private var image: NSImage?

    private var previewURL: URL? {
        session.resultScreenshotURL ?? session.stageScreenshotURL
    }

    private var caption: String {
        if session.resultScreenshotURL != nil {
            return "Result"
        }
        if session.stageScreenshotURL != nil {
            return "Stage"
        }
        return "Video"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Fit, not fill.
            //
            // Filling a landscape tile from a portrait capture — a Calculator
            // window, an inspector panel — crops away everything but a band
            // across the middle, and the thumbnail for a Calculator demo ends
            // up showing two rows of buttons and no window. In an app whose
            // whole job is producing demo recordings, the library not being
            // able to show you what a take is of is the wrong trade for a tidy
            // grid. Letterboxed on the deep ground the player already uses.
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    thumbnailPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if showCaption {
                Text(caption)
                    .font(ActionType.uiMicro)
                    .foregroundStyle(StageHUDTheme.textPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .padding(8)
            }

            VStack {
                Spacer()
                HStack(spacing: 6) {
                    if showDuration, let duration = session.formattedDuration {
                        badge(duration)
                    }
                    if showNoteCount, session.feedbackCount > 0 {
                        badge("\(session.feedbackCount) note\(session.feedbackCount == 1 ? "" : "s")")
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(StageHUDTheme.fieldDeep)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if showBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(StageHUDTheme.cardBorder, lineWidth: 1)
            }
        }
        .task(id: previewURL) {
            loadImage()
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(ActionType.mono(10, weight: .semibold))
            .foregroundStyle(StageHUDTheme.overlayInk.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(StageHUDTheme.overlayScrim.opacity(0.55), in: Capsule(style: .continuous))
    }

    /// Below this the centred label and the bottom-left duration badge occupy
    /// the same pixels and print over each other. The icon alone still says
    /// which kind of run it was, so the label is what gives way.
    private var placeholderFitsLabel: Bool {
        height >= 64
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            StageHUDTheme.appBackground

            VStack(spacing: placeholderFitsLabel ? 8 : 0) {
                Image(systemName: session.kind == .inspection ? "eye" : (session.kind == .drive ? "cursorarrow.click" : "film"))
                    .font(.system(size: placeholderFitsLabel ? 16 : 13, weight: .medium))
                    .foregroundStyle(StageHUDTheme.textMuted)
                if placeholderFitsLabel {
                    Text(session.isCalculatorTake ? session.actualResult : session.kind.rawValue)
                        .font(session.isCalculatorTake ? ActionType.bodyMono : ActionType.uiBodyStrong)
                        .foregroundStyle(StageHUDTheme.textSecondary)
                }
            }
        }
    }

    private func loadImage() {
        guard let previewURL else {
            image = nil
            return
        }
        image = NSImage(contentsOf: previewURL)
    }
}
