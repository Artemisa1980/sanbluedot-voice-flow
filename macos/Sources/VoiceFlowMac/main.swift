import AppKit

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

