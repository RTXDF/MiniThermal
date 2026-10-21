import Darwin

func acquireInstanceLock(at path: String) -> Int32? {
    let flags = O_CREAT | O_RDWR | O_NOFOLLOW
    var descriptor = open(path, flags, 0o600)
    if descriptor < 0 && errno == EACCES {
        // Legacy builds used the decimal literal 0600, leaving an unreadable lock.
        var metadata = stat()
        guard lstat(path, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1,
              lchmod(path, 0o600) == 0 else { return nil }
        descriptor = open(path, flags, 0o600)
    }
    guard descriptor >= 0 else { return nil }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        close(descriptor)
        return nil
    }
    guard fchmod(descriptor, 0o600) == 0 else {
        close(descriptor)
        return nil
    }
    return descriptor
}
