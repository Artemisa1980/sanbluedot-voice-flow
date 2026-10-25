import AppKit

// The engine is fed through a pipe. If it exits before reading, the default SIGPIPE
// action ends the whole app, and `try?` on the write cannot stop a signal: measured
// 2026-10-23, a write to a child that had exited killed the writer with status 141.
// Ignored, the write fails with EPIPE instead, which every write site already absorbs.
signal(SIGPIPE, SIG_IGN)

MainActor.assumeIsolated {
    let application = NSApplication.shared
    // A separately identified preview never constructs the real delegate, whose
    // initialization reads personal stores and initializes capture/permissions.
    let applicationDelegate: NSApplicationDelegate =
        Bundle.main.bundleIdentifier == FocusHomePreviewDelegate.bundleIdentifier
        ? FocusHomePreviewDelegate() : AppDelegate()
    application.delegate = applicationDelegate
    application.setActivationPolicy(.regular)
    application.run()
}

