/// Resource factories must run exactly once per candidate. A lazy compactMap's
/// `first` can evaluate its transform twice: once to locate the first non-nil
/// element and again to retrieve it. That is unsafe for CGEvent.tapCreate.
enum EventTapInstallation {
    static func firstAvailable<Candidate, Handle>(
        _ candidates: [Candidate], create: (Candidate) -> Handle?
    ) -> Handle? {
        for candidate in candidates {
            if let handle = create(candidate) { return handle }
        }
        return nil
    }
}
