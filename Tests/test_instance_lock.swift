import Foundation
import Darwin

@main enum InstanceLockTests {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("minithermal-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("instance.lock").path
        guard let first = acquireInstanceLock(at: path) else { check(false, "initial launch must acquire a lock"); return }
        close(first)
        guard let second = acquireInstanceLock(at: path) else { check(false, "restart must reopen the existing lock file"); return }
        check(acquireInstanceLock(at: path) == nil, "a concurrent launch must be rejected")
        var metadata = stat()
        check(lstat(path, &metadata) == 0 && metadata.st_mode & 0o777 == 0o600, "lock permissions must be owner read/write")
        close(second)
        check(chmod(path, 0o110) == 0, "prepare a legacy lock file")
        guard let migrated = acquireInstanceLock(at: path) else { check(false, "restart must repair the legacy permissions"); return }
        close(migrated)
        check(lstat(path, &metadata) == 0 && metadata.st_mode & 0o777 == 0o600, "legacy permissions must be repaired")
        let target = directory.appendingPathComponent("unrelated.txt")
        try "untouched".write(to: target, atomically: true, encoding: .utf8)
        let link = directory.appendingPathComponent("link.lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        check(acquireInstanceLock(at: link.path) == nil, "a symlink must not be used as the lock")
        print("PASS: launch, restart, duplicate prevention, legacy repair and symlink rejection")
    }
}
