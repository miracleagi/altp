import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func persistentKey(
    appName: String,
    bundleIdentifier: String?,
    title: String,
    subrole: String = "AXStandardWindow",
    document: String = "",
    identifier: String = ""
) -> String? {
    let applicationKey = WindowIdentityPolicy.applicationKey(
        bundleIdentifier: bundleIdentifier,
        appName: appName
    )
    return WindowIdentityPolicy.persistentWindowKey(
        applicationKey: applicationKey,
        appName: appName,
        bundleIdentifier: bundleIdentifier,
        title: title,
        subrole: subrole,
        document: document,
        identifier: identifier
    )
}

let documentBeforeTitleChange = persistentKey(
    appName: "Editor",
    bundleIdentifier: "com.example.editor",
    title: "Draft",
    document: "file:///tmp/report.md"
)
let documentAfterTitleChange = persistentKey(
    appName: "Editor",
    bundleIdentifier: "com.example.editor",
    title: "Report — Edited",
    document: "file:///tmp/report.md"
)
expect(
    documentBeforeTitleChange == documentAfterTitleChange
        && documentBeforeTitleChange != nil,
    "a stable document identity must survive title changes"
)
expect(
    persistentKey(
        appName: "Editor",
        bundleIdentifier: "com.example.editor",
        title: "Report",
        document: "file:///Volumes/Data/Report.md"
    ) != persistentKey(
        appName: "Editor",
        bundleIdentifier: "com.example.editor",
        title: "Report",
        document: "file:///Volumes/Data/report.md"
    ),
    "document identity must preserve case-sensitive paths"
)

let identifierBeforeTitleChange = persistentKey(
    appName: "Tool",
    bundleIdentifier: "com.example.tool",
    title: "Loading",
    identifier: "window-42"
)
let identifierAfterTitleChange = persistentKey(
    appName: "Tool",
    bundleIdentifier: "com.example.tool",
    title: "Ready",
    identifier: "window-42"
)
expect(
    identifierBeforeTitleChange == identifierAfterTitleChange
        && identifierBeforeTitleChange != nil,
    "a stable AX identifier must survive title changes"
)
expect(
    persistentKey(
        appName: "Tool",
        bundleIdentifier: "com.example.tool",
        title: "Untitled"
    ) == nil,
    "title-only and frame-only windows must not receive persistent identity"
)
expect(
    persistentKey(
        appName: "Tool",
        bundleIdentifier: "com.example.tool",
        title: "Same",
        identifier: "window-a"
    ) != persistentKey(
        appName: "Tool",
        bundleIdentifier: "com.example.tool",
        title: "Same",
        identifier: "window-b"
    ),
    "same-title windows with distinct identifiers must stay distinct"
)

let cursorBundleIdentifier = "com.todesktop.230313mzl4w4u92"
let cursorWorkspaceBeforeTitleChange = persistentKey(
    appName: "Cursor",
    bundleIdentifier: cursorBundleIdentifier,
    title: "One.swift — Altp",
    identifier: "cursor-window-1"
)
let cursorWorkspaceAfterTitleChange = persistentKey(
    appName: "Cursor",
    bundleIdentifier: cursorBundleIdentifier,
    title: "Two.swift — Altp",
    identifier: "cursor-window-1"
)
let secondCursorWindowInWorkspace = persistentKey(
    appName: "Cursor",
    bundleIdentifier: cursorBundleIdentifier,
    title: "README.md — Altp",
    identifier: "cursor-window-2"
)
expect(
    cursorWorkspaceBeforeTitleChange == cursorWorkspaceAfterTitleChange
        && cursorWorkspaceBeforeTitleChange != nil,
    "Cursor file-title changes must retain the workspace candidate identity"
)
expect(
    WindowIdentityPolicy.ambiguousPersistentKeys(
        in: [
            cursorWorkspaceBeforeTitleChange,
            secondCursorWindowInWorkspace
        ]
    ) == Set([cursorWorkspaceBeforeTitleChange!]),
    "multiple Cursor windows in one workspace must disable their shared persistent key"
)
expect(
    persistentKey(
        appName: "Cursor",
        bundleIdentifier: cursorBundleIdentifier,
        title: "One.swift — Workspace A",
        identifier: "cursor-window-1"
    ) != persistentKey(
        appName: "Cursor",
        bundleIdentifier: cursorBundleIdentifier,
        title: "One.swift — Workspace B",
        identifier: "cursor-window-2"
    ),
    "different Cursor workspaces must retain distinct candidate identities"
)
expect(
    persistentKey(
        appName: "Cursor",
        bundleIdentifier: cursorBundleIdentifier,
        title: "One.swift — Workspace",
        identifier: "cursor-window-1"
    ) != persistentKey(
        appName: "Cursor",
        bundleIdentifier: cursorBundleIdentifier,
        title: "One.swift — workspace",
        identifier: "cursor-window-2"
    ),
    "Cursor workspace identity must preserve case-sensitive names"
)
expect(
    persistentKey(
        appName: "Cursor",
        bundleIdentifier: cursorBundleIdentifier,
        title: "Settings",
        identifier: "cursor-settings"
    ) != nil,
    "Cursor may use a stable identifier when no workspace is present"
)
expect(
    persistentKey(
        appName: "Cursor",
        bundleIdentifier: cursorBundleIdentifier,
        title: "Settings"
    ) == nil,
    "Cursor without a workspace or identifier must not persist by title or frame"
)

expect(
    persistentKey(
        appName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        title: "Tab A",
        document: "https://example.com",
        identifier: "chrome-window-1"
    ) == nil,
    "Chrome window history must remain session-only across tab-title changes"
)

let sameLaunchSession = WindowIdentityPolicy.applicationSessionKey(
    applicationKey: "com.example.editor",
    processIdentifier: 42,
    launchTime: 1_000
)
expect(
    sameLaunchSession == WindowIdentityPolicy.applicationSessionKey(
        applicationKey: "com.example.editor",
        processIdentifier: 42,
        launchTime: 1_000
    ),
    "the same application launch must retain its session key"
)
expect(
    sameLaunchSession != WindowIdentityPolicy.applicationSessionKey(
        applicationKey: "com.example.editor",
        processIdentifier: 42,
        launchTime: 2_000
    ),
    "a reused PID with a different launch time must start a new app session"
)

let migratedDocumentKey = WindowIdentityPolicy.migratedLegacyPersistentKey(
    "com.example.editor|Old title|axstandardwindow|document:file:///tmp/report.md"
)
expect(
    migratedDocumentKey == documentBeforeTitleChange,
    "a reliable legacy document key must migrate without its volatile title"
)
let migratedIdentifierKey = WindowIdentityPolicy.migratedLegacyPersistentKey(
    "com.example.tool|Old title|axstandardwindow|identifier:window-42"
)
expect(
    migratedIdentifierKey == identifierBeforeTitleChange,
    "a reliable legacy identifier key must migrate without its volatile title"
)
expect(
    WindowIdentityPolicy.migratedLegacyPersistentKey(
        "com.example.tool|Old title|axstandardwindow|frame:0,0,1440,900"
    ) == nil,
    "legacy frame identities must be discarded"
)
expect(
    WindowIdentityPolicy.migratedLegacyPersistentKey(
        "\(cursorBundleIdentifier)|axstandardwindow|workspace:altp"
    ) == nil,
    "legacy shared Cursor workspace records must be discarded"
)
expect(
    WindowIdentityPolicy.migratedLegacyPersistentKey(
        "\(cursorBundleIdentifier)|axstandardwindow|frame:0,0,1440,900"
    ) == nil,
    "legacy Cursor frame records must be discarded"
)
let migratedCursorIdentifier = WindowIdentityPolicy.migratedLegacyPersistentKey(
    "\(cursorBundleIdentifier)|axstandardwindow|identifier:cursor-settings"
)
expect(
    migratedCursorIdentifier == persistentKey(
        appName: "Cursor",
        bundleIdentifier: cursorBundleIdentifier,
        title: "Settings",
        identifier: "cursor-settings"
    ),
    "a unique legacy Cursor identifier may be migrated"
)
expect(
    WindowIdentityPolicy.migratedLegacyPersistentKey(
        "com.google.chrome|Tab|axstandardwindow|identifier:chrome-window-1"
    ) == nil,
    "legacy Chrome title records must be discarded"
)
expect(
    WindowIdentityPolicy.migratedLegacyPersistentKey(
        "com.example.tool|Old title|axstandardwindow"
    ) == nil,
    "legacy title-only records must be discarded"
)
expect(
    WindowIdentityPolicy.migratedLegacyPersistentKey(
        identifierBeforeTitleChange!
    ) == identifierBeforeTitleChange,
    "current persistent keys must survive snapshot sanitation"
)

let fallbackKey = persistentKey(
    appName: "Example App",
    bundleIdentifier: "com.example.app",
    title: "Example App",
    subrole: "AXApplicationFallback",
    identifier: "window-server-fallback"
)
expect(
    fallbackKey == nil,
    "a synthetic application fallback must rely on its application representative"
)
expect(
    WindowIdentityPolicy.migratedLegacyPersistentKey(
        "com.example.app|Example App|axapplicationfallback|identifier:window-server-fallback"
    ) == nil,
    "legacy synthetic fallback history must not migrate into window records"
)

print("Window identity harness passed")
