import Foundation

/// Speech-owned speech queue. HUD controls and `speech.*` RPC share this
/// object as the single runtime truth.
@MainActor
final class SpeechQueue: ObservableObject {
    static let shared = SpeechQueue()

    private var dismissedFailureId: String?
    private var failureNotice: SpeechJob?
    @Published private(set) var snapshot = SpeechSnapshot(current: nil, queued: [], recent: [])

    var onSnapshotChange: ((SpeechSnapshot) -> Void)?

    private var synthesizer: SpeechSynthesizing
    private var player: SpeechPlaying
    private var voiceCatalog: SpeechVoiceListing
    private let limits: SpeechQueueLimits
    private let preferredVoiceForProvider: (String) -> String?

    private var jobs: [SpeechJob] = []
    private var currentIndex: Int?
    private var generation: UInt64 = 0
    private var synthesisTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var installed = false
    private var externalPlaybackOwner: UUID?
    private var resumeAfterExternalPlayback: String?
    private var deferredPlayback: (id: String, token: UInt64, payload: SpeechAudioPayload)?

    /// A transport-owned reservation. Only its owner may release it.
    func reserveExternalPlayback(owner: UUID) throws {
        guard externalPlaybackOwner == nil || externalPlaybackOwner == owner else {
            throw SpeechQueueError.providerFailed("Another voice session is speaking")
        }
        guard externalPlaybackOwner == nil else { return }
        externalPlaybackOwner = owner
        if let job = snapshot.current, job.state == .playing {
            _ = try pause(jobId: job.id)
            resumeAfterExternalPlayback = job.id
        }
        publish()
    }

    func releaseExternalPlayback(owner: UUID) {
        guard externalPlaybackOwner == owner else { return }
        externalPlaybackOwner = nil
        let resumeId = resumeAfterExternalPlayback
        resumeAfterExternalPlayback = nil
        if let deferred = deferredPlayback {
            deferredPlayback = nil
            beginPlayback(jobId: deferred.id, token: deferred.token, payload: deferred.payload)
        } else if let resumeId, snapshot.current?.id == resumeId, snapshot.current?.state == .paused {
            _ = try? resume(jobId: resumeId)
        }
        pump()
        publish()
    }

    init(
        synthesizer: SpeechSynthesizing? = nil,
        player: SpeechPlaying? = nil,
        voiceCatalog: SpeechVoiceListing? = nil,
        limits: SpeechQueueLimits = .default,
        preferredVoiceForProvider: ((String) -> String?)? = nil
    ) {
        self.synthesizer = synthesizer ?? UnconfiguredSpeechSynthesizer()
        self.player = player ?? NullSpeechPlayer()
        self.voiceCatalog = voiceCatalog ?? StaticSpeechVoiceCatalog()
        self.limits = limits
        self.preferredVoiceForProvider = preferredVoiceForProvider
            ?? { SpeechVoicePreferences.shared.preferredVoice(for: $0) }
        self.installed = synthesizer != nil && player != nil
    }

    func install(
        synthesizer: SpeechSynthesizing,
        player: SpeechPlaying,
        voiceCatalog: SpeechVoiceListing
    ) {
        halt(cancelQueued: true)
        self.synthesizer = synthesizer
        self.player = player
        self.voiceCatalog = voiceCatalog
        installed = true
        publish()
    }

    var isInstalled: Bool { installed }

    func voices() -> [SpeechVoiceInfo] {
        voiceCatalog.voices()
    }

    @discardableResult
    func enqueue(_ request: SpeechEnqueueRequest, playbackDeadline: Date? = nil) throws -> SpeechJob {
        guard installed else { throw SpeechQueueError.runtimeUnavailable }
        try SpeechEnqueueValidator.validate(request, limits: limits, queuedCount: activeCount)

        let voice = request.voice.flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } ?? preferredVoiceForProvider(request.provider)

        var job = SpeechJob(
            id: "spk_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))",
            state: .queued,
            text: request.text,
            provider: request.provider,
            model: request.model,
            voice: voice,
            rate: request.rate,
            instructions: request.instructions,
            voiceSettings: request.voiceSettings,
            cachePolicy: request.cachePolicy,
            source: request.source,
            error: nil,
            currentTime: 0,
            duration: 0,
            createdAt: Date(),
            generation: 0,
            playbackDeadline: playbackDeadline
        )
        jobs.append(job)
        publish()
        pump()
        job = jobs.first(where: { $0.id == job.id }) ?? job
        return job
    }

    func status() -> SpeechSnapshot {
        snapshot
    }

    func pause(jobId: String? = nil) throws -> SpeechSnapshot {
        let job = try requireCurrent(jobId, missing: .nothingToPause)
        guard job.state == .playing else { throw SpeechQueueError.nothingToPause }
        player.pause()
        mutateCurrent { current in
            current.state = .paused
            current.currentTime = player.currentTime
            current.duration = player.duration
        }
        stopPlaybackClock()
        publish()
        return snapshot
    }

    func resume(jobId: String? = nil) throws -> SpeechSnapshot {
        guard externalPlaybackOwner == nil else {
            throw SpeechQueueError.providerFailed("Waiting for the voice session to finish")
        }
        let job = try requireCurrent(jobId, missing: .nothingToResume)
        guard job.state == .paused else { throw SpeechQueueError.nothingToResume }
        player.resume()
        mutateCurrent { current in
            current.state = player.isPlaying ? .playing : .paused
            current.currentTime = player.currentTime
            current.duration = player.duration
        }
        publish()
        if snapshot.current?.state == .playing {
            startPlaybackClock()
        }
        return snapshot
    }

    func seek(seconds: TimeInterval, jobId: String? = nil) throws -> SpeechSnapshot {
        let job = try requireCurrent(jobId, missing: .nothingToSeek)
        guard job.state == .playing || job.state == .paused else {
            throw SpeechQueueError.nothingToSeek
        }
        _ = player.seek(to: max(0, seconds))
        mutateCurrent { current in
            current.currentTime = player.currentTime
            current.duration = player.duration
        }
        publish()
        return snapshot
    }

    @discardableResult
    func stop(jobId: String? = nil) throws -> SpeechSnapshot {
        if let jobId, snapshot.current?.id != jobId {
            throw SpeechQueueError.jobMismatch(jobId)
        }
        if snapshot.current?.state == .failed {
            dismissedFailureId = snapshot.current?.id
        }
        failureNotice = nil
        halt(cancelQueued: true)
        publish()
        return snapshot
    }

    @discardableResult
    func next(jobId: String? = nil) throws -> SpeechSnapshot {
        if let jobId {
            _ = try requireCurrent(jobId, missing: .jobMismatch(jobId))
        }
        halt(cancelQueued: false)
        pump()
        publish()
        return snapshot
    }

    func dismissFailure() {
        dismissedFailureId = failureNotice?.id
        failureNotice = nil
        publish()
    }

    // MARK: - Pump

    private var activeCount: Int {
        jobs.filter { job in
            switch job.state {
            case .queued, .generating, .playing, .paused:
                return true
            case .completed, .cancelled, .failed:
                return false
            }
        }.count
    }

    private func pump() {
        guard externalPlaybackOwner == nil else { return }
        if let currentIndex {
            let state = jobs[currentIndex].state
            if state == .generating || state == .playing || state == .paused {
                return
            }
        }
        for index in jobs.indices where jobs[index].state == .queued {
            if let deadline = jobs[index].playbackDeadline, deadline <= Date() {
                jobs[index].state = .cancelled
            }
        }
        guard let nextIndex = jobs.firstIndex(where: { $0.state == .queued }) else {
            currentIndex = nil
            stopPlaybackClock()
            publish()
            return
        }
        beginGeneration(at: nextIndex)
    }

    private func beginGeneration(at index: Int) {
        currentIndex = index
        generation &+= 1
        let token = generation
        jobs[index].generation = token
        jobs[index].state = .generating
        jobs[index].error = nil
        // Publishing may prune history and shift indices. Capture the job first.
        let job = jobs[index]
        publish()

        let request = SpeechSynthesisRequest(
            text: job.text,
            provider: job.provider,
            model: job.model,
            voice: job.voice,
            rate: job.rate,
            instructions: job.instructions,
            voiceSettings: job.voiceSettings,
            cachePolicy: job.cachePolicy
        )
        let jobId = job.id

        synthesisTask?.cancel()
        synthesisTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.synthesizer.synthesize(request)
                guard !Task.isCancelled else { return }
                self.beginPlayback(jobId: jobId, token: token, payload: payload)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.fail(jobId: jobId, token: token, error: error)
            }
        }
    }

    private func beginPlayback(jobId: String, token: UInt64, payload: SpeechAudioPayload) {
        guard token == generation,
              let index = jobs.firstIndex(where: { $0.id == jobId }),
              jobs[index].state == .generating
        else { return }
        if externalPlaybackOwner != nil {
            deferredPlayback = (jobId, token, payload)
            return
        }
        if let deadline = jobs[index].playbackDeadline, deadline <= Date() {
            jobs[index].state = .cancelled
            currentIndex = nil
            publish()
            pump()
            return
        }

        do {
            try player.play(data: payload.data, format: payload.format, failure: { [weak self] error in
                self?.fail(jobId: jobId, token: token, error: error)
            }) { [weak self] in
                self?.finishPlayback(jobId: jobId, token: token)
            }
            guard token == generation, jobs.indices.contains(index),
                  jobs[index].id == jobId, jobs[index].state == .generating else { return }
            jobs[index].state = .playing
            jobs[index].voice = payload.voice
            jobs[index].provider = payload.provider
            jobs[index].currentTime = player.currentTime
            jobs[index].duration = player.duration
            startPlaybackClock()
            publish()
        } catch {
            fail(jobId: jobId, token: token, error: error)
        }
    }

    private func finishPlayback(jobId: String, token: UInt64) {
        guard token == generation,
              let index = jobs.firstIndex(where: { $0.id == jobId })
        else { return }
        let state = jobs[index].state
        guard state == .playing || state == .paused else { return }
        jobs[index].state = .completed
        jobs[index].currentTime = player.duration
        jobs[index].duration = player.duration
        stopPlaybackClock()
        currentIndex = nil
        publish()
        pump()
    }

    private func fail(jobId: String, token: UInt64, error: Error) {
        guard token == generation,
              let index = jobs.firstIndex(where: { $0.id == jobId })
        else { return }
        guard [.generating, .playing, .paused].contains(jobs[index].state) else { return }
        let message = SpeechErrorRedactor.message(from: error)
        jobs[index].state = .failed
        jobs[index].error = message
        failureNotice = jobs[index]
        stopPlaybackClock()
        player.stop()
        currentIndex = nil
        publish()
        DiagnosticLog.shared.error("Speech job \(jobId) failed: \(message)")
        pump()
    }

    private func halt(cancelQueued: Bool) {
        deferredPlayback = nil
        resumeAfterExternalPlayback = nil
        generation &+= 1
        synthesisTask?.cancel()
        synthesisTask = nil
        stopPlaybackClock()
        player.stop()

        if let currentIndex, jobs.indices.contains(currentIndex) {
            switch jobs[currentIndex].state {
            case .queued, .generating, .playing, .paused:
                jobs[currentIndex].state = .cancelled
            case .completed, .cancelled, .failed:
                break
            }
        }
        if cancelQueued {
            for index in jobs.indices where jobs[index].state == .queued {
                jobs[index].state = .cancelled
            }
        }
        currentIndex = nil
    }

    private func requireCurrent(_ jobId: String?, missing: SpeechQueueError) throws -> SpeechJob {
        guard let currentIndex, jobs.indices.contains(currentIndex) else {
            throw missing
        }
        let job = jobs[currentIndex]
        if let jobId, job.id != jobId {
            throw SpeechQueueError.jobMismatch(jobId)
        }
        return job
    }

    private func mutateCurrent(_ body: (inout SpeechJob) -> Void) {
        guard let currentIndex, jobs.indices.contains(currentIndex) else { return }
        body(&jobs[currentIndex])
    }

    private func startPlaybackClock() {
        stopPlaybackClock()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPlaybackClock()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopPlaybackClock() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func refreshPlaybackClock() {
        guard let currentIndex, jobs.indices.contains(currentIndex) else { return }
        let state = jobs[currentIndex].state
        guard state == .playing || state == .paused else { return }
        jobs[currentIndex].currentTime = player.currentTime
        jobs[currentIndex].duration = player.duration
        publish()
    }

    private func publish() {
        pruneTerminalJobs()
        let current: SpeechJob?
        if let currentIndex, jobs.indices.contains(currentIndex) {
            current = jobs[currentIndex]
        } else {
            // A historical failure must not reappear after a newer job ends.
            current = jobs.last.flatMap { job in
                job.state == .failed && job.id != dismissedFailureId ? job : nil
            }
        }
        let queued = jobs.filter { $0.state == .queued }
        let recent = jobs.filter { job in
            job.state == .completed || job.state == .cancelled || job.state == .failed
        }.suffix(limits.maxRecentJobs)
        let snap = SpeechSnapshot(current: current, queued: queued, recent: Array(recent), failure: failureNotice)
        snapshot = snap
        onSnapshotChange?(snap)
    }

    private func pruneTerminalJobs() {
        let currentId = currentIndex.flatMap { jobs.indices.contains($0) ? jobs[$0].id : nil }
        let surplus = jobs.filter(isTerminal).count - limits.maxRecentJobs
        guard surplus > 0 else { return }
        var removed = 0
        jobs.removeAll { job in
            guard removed < surplus else { return false }
            guard isTerminal(job), job.id != currentId else { return false }
            removed += 1
            return true
        }
        if let currentId {
            currentIndex = jobs.firstIndex(where: { $0.id == currentId })
        }
    }

    private func isTerminal(_ job: SpeechJob) -> Bool {
        switch job.state {
        case .completed, .cancelled, .failed:
            return true
        case .queued, .generating, .playing, .paused:
            return false
        }
    }
}

enum SpeechEnqueueValidator {
    static let forbiddenAudioKeys: Set<String> = [
        "audioUrl", "audioURL", "url", "href", "sourceUrl", "sourceURL",
        "link", "audio", "audioBase64", "file", "path",
    ]

    static func validate(_ request: SpeechEnqueueRequest, limits: SpeechQueueLimits, queuedCount: Int) throws {
        if queuedCount >= limits.maxJobs {
            throw SpeechQueueError.queueFull(limit: limits.maxJobs)
        }
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw SpeechQueueError.emptyText }
        if text.count > limits.maxTextCharacters {
            throw SpeechQueueError.textTooLong(limit: limits.maxTextCharacters)
        }
        if let instructions = request.instructions, instructions.count > limits.maxInstructionsCharacters {
            throw SpeechQueueError.instructionsTooLong(limit: limits.maxInstructionsCharacters)
        }
        if request.rate < 0.25 || request.rate > 4.0 {
            throw SpeechQueueError.invalidRate
        }
        _ = try SpeechProviders.normalize(request.provider)
        try validateSource(request.source, limit: limits.maxSourceFieldCharacters)
    }

    static func validateSource(_ source: SpeechSourceMetadata?, limit: Int) throws {
        guard let source else { return }
        for value in [source.kind, source.label, source.taskId, source.sessionId] {
            guard let value else { continue }
            if value.count > limit {
                throw SpeechQueueError.sourceLinkForbidden
            }
            if looksLikeLink(value) {
                throw SpeechQueueError.sourceLinkForbidden
            }
        }
    }

    static func looksLikeLink(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("://") || lower.hasPrefix("http:") || lower.hasPrefix("https:")
    }

    static func rejectRemoteAudio(in params: JSON) throws {
        guard case .object(let object) = params else { return }
        for key in object.keys where forbiddenAudioKeys.contains(key) {
            throw SpeechQueueError.remoteAudioForbidden
        }
        if let source = object["source"], case .object(let sourceObject) = source {
            for key in ["url", "href", "link", "audioUrl", "path"] where sourceObject[key] != nil {
                throw SpeechQueueError.sourceLinkForbidden
            }
        }
    }
}
