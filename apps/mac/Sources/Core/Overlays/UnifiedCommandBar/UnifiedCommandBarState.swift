import AppKit
import Combine
import SwiftUI

/// State for the unified command bar — one bar for search, slash-commands and
/// (later) voice. It **composes** the existing `OmniSearchState` (which itself
/// owns the `CommandBarState` slash-command engine), so search + commands are
/// reused verbatim. This layer only adds the single text binding, the entry
/// mode, and the "what should the panel show" detail computation.
///
/// Phase A: search + commands. Voice (`VoiceCommandState`) and the assistant
/// handoff are wired in later phases.
final class UnifiedCommandBarState: ObservableObject {
    enum Mode { case command, search, voice }

    /// What the expansion panel under the bar should render. `.none` keeps the
    /// bar slim — detail is revealed only when there's something to show.
    enum Detail: Equatable { case none, search, command, voice, welcome }

    /// The single text-field binding. Forwarded verbatim into the composed
    /// engine, which routes a leading "/" into command mode (the visible trigger)
    /// and everything else into search.
    @Published var query: String = "" {
        didSet {
            guard query != search.query else { return }
            search.query = query
        }
    }

    /// Composed engines. `search.command` is the slash-command engine; `voice`
    /// is reused **verbatim** (its deadlock-safe DiagnosticLog observer is the
    /// highest-risk code to rewrite, so we compose rather than absorb it).
    let search = OmniSearchState()
    let voice = VoiceCommandState()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Re-publish nested engine changes so the view re-renders (and `detail`
        // recomputes) whenever results, command suggestions, or voice phase update.
        for child in [search.objectWillChange, voice.objectWillChange] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    /// A leading "/" is the visible command trigger.
    var commandMode: Bool { query.hasPrefix("/") }

    /// Voice has taken over the bar (listening / transcribing / showing a result).
    var voiceActive: Bool { voice.phase != .idle }

    /// Typed free text that reads as a Lattices *question* → the send button
    /// becomes an "ask" affordance and Enter hands off to the assistant.
    var wantsAssistant: Bool {
        !voiceActive && !commandMode && IntentHeuristics.shouldAskAssistant(query)
    }

    private var voiceHasContent: Bool {
        !voice.partialText.isEmpty || !voice.finalText.isEmpty
            || voice.intentName != nil || !voice.resultItems.isEmpty
            || !voice.resultSummary.isEmpty || voice.executionError != nil
    }

    var detail: Detail {
        // Voice wins while it's active — reveal its detail once there's something
        // to show (the bar itself reflects the listening state before then).
        if voiceActive { return voiceHasContent ? .voice : .none }
        if commandMode {
            // `/` is the visible trigger: command suggestions, filtered as you type
            // (↑/↓ navigate, ⇥ complete, ↵ run).
            return search.command.suggestions.isEmpty ? .none : .command
        }
        // Empty bar → a short welcome; plain text → search.
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return .welcome }
        return search.results.isEmpty ? .none : .search
    }

    func moveSelection(_ delta: Int) { search.moveSelection(delta) }
}
