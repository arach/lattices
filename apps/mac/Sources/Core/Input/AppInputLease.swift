import Darwin
import Foundation

/// One menu-bar app owns the global input services, across dev/release bundle
/// identities. The kernel releases this lease on exit, including crashes.
/// Never unlink the lock file: that would allow a new inode and a second owner.
final class AppInputLease {
    enum Failure: Error { case occupied; case system(Int32) }
    private let descriptor: Int32

    static func isPeer(bundleIdentifier: String?, pid: pid_t, ownPID: pid_t) -> Bool {
        pid != ownPID && (bundleIdentifier == "dev.lattices.app"
            || bundleIdentifier == "dev.lattices.app.dev")
    }

    init(path: String) throws {
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure.system(errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK { throw Failure.occupied }
            throw Failure.system(code)
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }
}
