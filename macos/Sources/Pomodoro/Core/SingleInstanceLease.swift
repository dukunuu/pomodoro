import Foundation
import Darwin

/// A kernel-held lease, released on exit/crash. Never unlink the lock file:
/// deleting it would let a new process lock a different inode.
final class SingleInstanceLease {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

    static func acquire(at path: URL) throws -> SingleInstanceLease? {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(path.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return SingleInstanceLease(descriptor) }
        let failure = errno
        close(descriptor)
        if failure == EWOULDBLOCK { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
    }
}
