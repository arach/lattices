import SwiftUI

/// Scenarios: one table, three states.
///
/// A scenario is a list of instructions, and it stays a list of instructions
/// the whole way through. The grid — `#`, `VERB`, `STEP`, `TARGET`, `NOTES` —
/// is fixed and never rearranges; planning, running and reviewing are three
/// states of the same object rather than three different objects. So the row
/// you read before the run is the row you watch during it and the row you
/// judge after it, in the same place, at the same width, in the same face.
///
/// This replaces four nested cards — a list card holding scenario cards, a
/// header card holding chips, a plan card holding step rows, and a permanently
/// reserved 280pt notes rail holding a field box and note boxes — with one
/// ruled table on paper. It is the same table language as the Runs ledger and
/// the start page, which were the two surfaces that already got this right.
struct ActionWorkspaceView: View {
    @ObservedObject var model: ActionLauncherViewModel
    var onOpenLibrary: () -> Void

    /// The step whose notes are open. A note belongs to a step, so it opens
    /// under that step rather than in a rail that is empty most of the time.
    @State private var openStepID: String?

    // MARK: - Geometry
    //
    // Stated once so the header and the rows cannot drift apart. The moment a
    // column header sits over a different edge than its values, the table stops
    // being a table.

    private static let indexWidth: CGFloat = 26
    private static let verbWidth: CGFloat = 86
    private static let targetWidth: CGFloat = 176
    private static let notesWidth: CGFloat = 78
    /// Wide enough for a plan to breathe, narrow enough that the step column is
    /// not a hundred points of empty paper between the verb and its target.
    private static let pageWidth: CGFloat = 760

    /// Which of the three states the page is in.
    private enum PageState {
        case plan
        case running
        case review
    }

    var body: some View {
        Group {
            if let scenario = model.selectedScenario {
                scenarioPage(scenario)
            } else if let first = model.scenarios.first {
                // The list rail is gone, so "nothing selected" is not a state
                // the page can sit in — it falls through to the first scenario
                // the way a switcher does.
                scenarioPage(first)
            } else {
                startPage
            }
        }
        .frame(maxWidth: Self.pageWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func state(for scenario: ActionScenarioDocument) -> PageState {
        if model.isRunningGuidedDemo {
            return .running
        }
        if hasTake(scenario), scenario.phase == .review {
            return .review
        }
        return .plan
    }

    // MARK: - The page

    @ViewBuilder
    private func scenarioPage(_ scenario: ActionScenarioDocument) -> some View {
        let pageState = state(for: scenario)

        VStack(alignment: .leading, spacing: 0) {
            pageHeader(scenario, state: pageState)

            if pageState == .review, let session = sessionForScenario(scenario) {
                takeSlab(session)
                    .padding(.top, 22)
            }

            planTable(scenario.steps, interactive: pageState == .plan)
                .padding(.top, pageState == .review ? 20 : 26)

            if pageState == .plan {
                goalField
                    .padding(.top, 24)
            }

            actionRow(scenario, state: pageState)
                .padding(.top, 22)
        }
    }

    /// The scenario's name *is* the switcher.
    ///
    /// A separate chip beside the title printed the same words twice, and with
    /// one scenario saved it printed them twice to offer a choice of one. The
    /// name is the biggest thing on the page and the thing you would reach for
    /// anyway, so it takes the menu: New, Delete, and every other scenario.
    private func pageHeader(_ scenario: ActionScenarioDocument, state pageState: PageState) -> some View {
        let position = (model.scenarios.firstIndex(where: { $0.id == scenario.id }) ?? 0) + 1

        return VStack(alignment: .leading, spacing: 3) {
            // The state is stated. It used to be legible only from a button
            // offering to leave it — a control labelled "Last take" was the
            // only way to know you were looking at the plan.
            Text(eyebrow(for: scenario, state: pageState))
                .font(ActionType.label)
                .tracking(ActionType.eyebrowTracking)
                .foregroundStyle(StageHUDTheme.textMuted)

            Menu {
                ForEach(model.scenarios) { item in
                    Button(item.title) {
                        openStepID = nil
                        model.selectScenario(item)
                    }
                }
                Divider()
                Button("New scenario") {
                    openStepID = nil
                    model.startCalculatorScenario()
                }
                if hasTake(scenario) {
                    Button("Open in Library", action: onOpenLibrary)
                }
                Divider()
                Button("Delete \(scenario.title)…", role: .destructive) {
                    model.deleteScenario(scenario)
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(scenario.title)
                        .font(ActionType.uiHeadline)
                        .tracking(ActionType.headlineTracking)
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(ActionIcon.micro)
                        .foregroundStyle(StageHUDTheme.textMuted)

                    if model.scenarios.count > 1 {
                        Text("\(position) of \(model.scenarios.count)")
                            .font(ActionType.monoCaption)
                            .foregroundStyle(StageHUDTheme.textMuted)
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func eyebrow(for scenario: ActionScenarioDocument, state pageState: PageState) -> String {
        switch pageState {
        case .plan:
            return "PLAN"
        case .running:
            return "RUNNING"
        case .review:
            guard let session = sessionForScenario(scenario), let date = session.startedAt else {
                return "TAKE"
            }
            let ago = Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
            return "TAKE · \(ago.uppercased())"
        }
    }

    // MARK: - The table

    /// The one table. `interactive` is false while a run is in flight and on
    /// the start page, where there is nothing yet to annotate.
    private func planTable(_ steps: [ActionScenarioStep], interactive: Bool) -> some View {
        // The notes column earns its header only once something has been said.
        // A column heading over four blank cells is furniture describing an
        // absence, and on the start page every cell is blank by definition.
        let showsNotes = steps.contains { !notesColumn($0).isEmpty }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ActionColumnHeader(title: "#")
                    .frame(width: Self.indexWidth)
                ActionColumnHeader(title: "VERB")
                    .frame(width: Self.verbWidth)
                ActionColumnHeader(title: "STEP")
                    .frame(maxWidth: .infinity)
                ActionColumnHeader(title: "TARGET", alignment: .trailing)
                    .frame(width: Self.targetWidth)
                if showsNotes {
                    ActionColumnHeader(title: "NOTES", alignment: .trailing)
                        .frame(width: Self.notesWidth)
                }
            }
            .padding(.bottom, 7)

            ActionRule()

            ForEach(steps) { step in
                let open = interactive && openStepID == step.id

                VStack(alignment: .leading, spacing: 0) {
                    stepRow(step, interactive: interactive, showsNotes: showsNotes)

                    if open {
                        stepNotes(step)
                    }
                }
                // The tint holds the row *and* what it opened, bled past the
                // table's own edge so the pair reads as one band across the
                // page rather than as a highlighted row with loose controls
                // sitting on paper underneath it.
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(open ? StageHUDTheme.textPrimary.opacity(0.035) : Color.clear)
                        .padding(.horizontal, -10)
                )
            }

            ActionRule(opacity: 0.55)
        }
        .animation(.easeOut(duration: 0.14), value: openStepID)
    }

    /// One line of the plan: number, verb, what it does, what it does it to,
    /// and whether anything has been said about it.
    ///
    /// The index is numbered because these genuinely are a sequence — step 3
    /// types into the total step 2 produced — and not because numbering a list
    /// looks orderly. Three tones are the whole hierarchy of the row: muted
    /// number, secondary verb, full-ink step.
    private func stepRow(_ step: ActionScenarioStep, interactive: Bool, showsNotes: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(String(format: "%02d", step.index))
                .font(ActionType.monoCaption)
                .foregroundStyle(StageHUDTheme.textMuted)
                .frame(width: Self.indexWidth, alignment: .leading)

            Text(step.action)
                .font(ActionType.monoCaption)
                .foregroundStyle(StageHUDTheme.textSecondary)
                .frame(width: Self.verbWidth, alignment: .leading)

            Text(step.description)
                .font(ActionType.uiRow)
                .foregroundStyle(step.isSkipped ? StageHUDTheme.textMuted : StageHUDTheme.textPrimary)
                .strikethrough(step.isSkipped)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(step.targetSummary ?? "—")
                .font(ActionType.monoCaption)
                .foregroundStyle(StageHUDTheme.textMuted)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(width: Self.targetWidth, alignment: .trailing)

            if showsNotes {
                Text(notesColumn(step))
                    .font(ActionType.monoCaption)
                    .foregroundStyle(StageHUDTheme.textMuted)
                    .frame(width: Self.notesWidth, alignment: .trailing)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard interactive else { return }
            if openStepID == step.id {
                openStepID = nil
            } else {
                openStepID = step.id
                model.selectScenarioStep(step)
            }
        }
    }

    /// Blank unless there is something to say. A column of dashes is furniture.
    private func notesColumn(_ step: ActionScenarioStep) -> String {
        if step.isSkipped {
            return "skipped"
        }
        let count = step.feedback.count
        guard count > 0 else { return "" }
        return "\(count) note\(count == 1 ? "" : "s")"
    }

    /// The context the click earns, aligned under the STEP column it belongs
    /// to. This is what the 280pt rail was for, minus the rail, minus the
    /// heading that said "Step notes" over a panel that said "Select a step."
    private func stepNotes(_ step: ActionScenarioStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(step.feedback) { item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("—")
                        .font(ActionType.monoCaption)
                        .foregroundStyle(StageHUDTheme.textMuted)
                    Text(item.instruction)
                        .font(ActionType.uiRow)
                        .foregroundStyle(StageHUDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("NOTE")
                    .font(ActionType.label)
                    .tracking(ActionType.labelTracking)
                    .foregroundStyle(StageHUDTheme.textMuted)
                TextField(
                    "Wait for Calculator to finish opening",
                    text: $model.scenarioStepFeedbackDraft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(ActionType.uiRow)
                .foregroundStyle(StageHUDTheme.textPrimary)
                .lineLimit(1...3)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) { ActionRule() }
            }

            HStack(spacing: 8) {
                chipButton("ADD NOTE") {
                    model.addFeedbackToSelectedScenarioStep()
                }
                .disabled(model.scenarioStepFeedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                chipButton(step.isSkipped ? "INCLUDE" : "SKIP") {
                    model.toggleSkipScenarioStep(step.id)
                }
            }
        }
        .padding(.leading, Self.indexWidth + Self.verbWidth)
        .padding(.top, 2)
        .padding(.bottom, 16)
        .transition(.opacity)
    }

    // MARK: - The take

    private func takeSlab(_ session: ActionSessionSummary) -> some View {
        ActionSessionPreviewView(session: session, model: model)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(StageHUDTheme.cardBorder, lineWidth: StageHUDTheme.hairline)
            )
    }

    // MARK: - Actions
    //
    // One primary per state, and it is the same quiet button the launcher
    // header and Settings use. The page used to carry two primaries in its
    // detail header and a third in the launcher header above it.

    @ViewBuilder
    private func actionRow(_ scenario: ActionScenarioDocument, state pageState: PageState) -> some View {
        switch pageState {
        case .plan:
            HStack(spacing: 12) {
                Button("Run") {
                    model.approveAndRunSelectedScenario()
                }
                .buttonStyle(ActionQuietButtonStyle(shortcut: "⏎"))

                if hasTake(scenario) {
                    chipButton("LAST TAKE") { model.setFlowPhase(.review) }
                }

                Text("\(scenario.targetAppName) · \(scenario.steps.count) steps")
                    .font(ActionType.monoCaption)
                    .foregroundStyle(StageHUDTheme.textMuted)

                Spacer(minLength: 0)
            }

        case .running:
            HStack(spacing: 12) {
                // Coral means a drive is live, on Home and here. It is the only
                // colour on the page while a run is in flight.
                Circle()
                    .fill(StageHUDTheme.fieldAccent)
                    .frame(width: 7, height: 7)

                Text(model.guidedDemoStatus)
                    .font(ActionType.monoCaption)
                    .foregroundStyle(StageHUDTheme.textSecondary)
                    .lineLimit(1)

                chipButton("STOP") { model.stopAllDrives() }

                Spacer(minLength: 0)
            }

        case .review:
            HStack(spacing: 12) {
                Button("Run again") {
                    model.approveAndRunSelectedScenario()
                }
                .buttonStyle(ActionQuietButtonStyle())

                chipButton("PLAN") { model.setFlowPhase(.edit) }

                if let session = sessionForScenario(scenario) {
                    chipButton("REPLAY") { model.replaySession(session) }
                    chipButton("FINDER") { model.revealSession(session) }
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// The chip: mono, tracked, hairline. The secondary everywhere on this page
    /// and in the Home ledger's open row.
    private func chipButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(ActionType.label)
                .tracking(ActionType.labelTracking)
                .foregroundStyle(StageHUDTheme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(StageHUDTheme.textPrimary.opacity(0.22), lineWidth: StageHUDTheme.hairline)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Start

    /// The start page is not an empty state that happens to show a preview. It
    /// is the same table, in its first state, with nothing yet saved.
    ///
    /// It used to say "No scenarios yet", explain in a paragraph what a
    /// scenario is, and offer a button — the generic three-part empty state
    /// that could sit in any app, telling you about a thing instead of showing
    /// it to you. Action ships exactly one preset and it is four steps long.
    /// Four steps fit on the screen.
    private var startPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PRESET")
                .font(ActionType.label)
                .tracking(ActionType.eyebrowTracking)
                .foregroundStyle(StageHUDTheme.textMuted)

            Text("Calculator demo")
                .font(ActionType.uiHeadline)
                .tracking(ActionType.headlineTracking)
                .foregroundStyle(StageHUDTheme.textPrimary)
                .padding(.top, 5)

            planTable(ActionScenarioPresets.calculatorDemoSteps(), interactive: false)
                .padding(.top, 26)

            goalField
                .padding(.top, 24)

            HStack(spacing: 12) {
                Button("Start") {
                    model.startCalculatorScenario()
                }
                .buttonStyle(ActionQuietButtonStyle(shortcut: "⏎"))
                .disabled(model.isRunningGuidedDemo)

                // Only when it has something to say. The initial value of this
                // status is the word "Ready", and a bare "Ready" beside a
                // button, before anything has been asked of the app, reads as
                // debug output rather than as feedback.
                if model.guidedDemoStatus != ActionLauncherViewModel.idleStatus {
                    Text(model.guidedDemoStatus)
                        .font(ActionType.monoCaption)
                        .foregroundStyle(StageHUDTheme.textMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 22)
        }
    }

    /// The goal, on a rule rather than in a box.
    ///
    /// A filled, bordered, rounded field is four pieces of furniture around one
    /// line of text. A hairline under the text says the same thing — you can
    /// type here — and leaves the page made of one kind of mark.
    private var goalField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("GOAL")
                .font(ActionType.label)
                .tracking(ActionType.labelTracking)
                .foregroundStyle(StageHUDTheme.textMuted)
            // "What this demo is for", not "what should this demo show" — the
            // goal is saved on the scenario and shown back, but it does not
            // choose the steps: the preset's Calculator steps are the same
            // whatever is typed here. A placeholder that asks the operator to
            // describe the demo they want promises authoring the app cannot do
            // yet. See the note in ActionScenarioPresets.makeCalculatorScenario.
            TextField("What this demo is for", text: $model.scenarioDraftGoal, axis: .vertical)
                .textFieldStyle(.plain)
                .font(ActionType.uiRow)
                .foregroundStyle(StageHUDTheme.textPrimary)
                .lineLimit(1...3)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) { ActionRule() }
        }
    }

    // MARK: - Helpers

    private func hasTake(_ scenario: ActionScenarioDocument) -> Bool {
        scenario.latestSessionId != nil || !scenario.sessionIds.isEmpty
    }

    private func sessionForScenario(_ scenario: ActionScenarioDocument) -> ActionSessionSummary? {
        if let latest = scenario.latestSessionId,
           let session = model.recentSessions.first(where: { $0.sessionId == latest || $0.id == latest }) {
            return session
        }
        for id in scenario.sessionIds {
            if let session = model.recentSessions.first(where: { $0.sessionId == id || $0.id == id }) {
                return session
            }
        }
        return model.selectedSession
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
