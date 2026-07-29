import Foundation

final class WindowItem {
    let identity: String
    let persistentMemoryKey: String?
    let appMemoryKey: String
    let appSessionKey: String
    let sessionMemoryKey: String

    init(
        identity: String,
        persistentMemoryKey: String?,
        appMemoryKey: String,
        appSessionKey: String
    ) {
        self.identity = identity
        self.persistentMemoryKey = persistentMemoryKey
        self.appMemoryKey = appMemoryKey
        self.appSessionKey = appSessionKey
        self.sessionMemoryKey = "\(appSessionKey)|window:\(identity)"
    }

    func representsSameWindow(as other: WindowItem) -> Bool {
        identity == other.identity
    }
}

struct SnapshotFixture: Codable {
    var records: [String: RecordFixture]
    var appRecords: [String: RecordFixture]
}

struct RecordFixture: Codable {
    var selectionCount: Int
    var lastSelectedAt: TimeInterval
    var queryHits: [String: Int]
    var appSessionKey: String?
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func isolatedDefaults(_ suffix: String) -> UserDefaults {
    let suiteName = "com.miracleagi.altp.tests.\(suffix).\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fputs("FAIL: could not create isolated UserDefaults\n", stderr)
        exit(1)
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

let appKey = "com.example.editor"
let persistentKey = WindowIdentityPolicy.persistentWindowKey(
    applicationKey: appKey,
    appName: "Editor",
    bundleIdentifier: appKey,
    title: "Report",
    subrole: "AXStandardWindow",
    document: "file:///tmp/report.md",
    identifier: ""
)!
let sessionKey = WindowIdentityPolicy.applicationSessionKey(
    applicationKey: appKey,
    processIdentifier: 42,
    launchTime: 2_000
)
let source = WindowItem(
    identity: "source",
    persistentMemoryKey: nil,
    appMemoryKey: "com.example.source",
    appSessionKey: "source-session"
)
let target = WindowItem(
    identity: "target",
    persistentMemoryKey: persistentKey,
    appMemoryKey: appKey,
    appSessionKey: sessionKey
)

let orderingMemory = WindowSelectionMemory(
    defaults: isolatedDefaults("ordering")
)
orderingMemory.recordSelection(
    target,
    query: "",
    from: source,
    selectedAt: 200_000
)
orderingMemory.recordSelection(
    target,
    query: "",
    from: source,
    selectedAt: 100_000
)

let persistentRank = orderingMemory.persistentRank(
    for: target,
    referenceTime: 200_000
)
let expectedPersistentScore = WindowRankingPolicy.persistentScore(
    selectionCount: 2,
    lastSelectedAt: 200_000,
    maximumScore: WindowRankingPolicy.maximumPersistentWindowScore,
    referenceTime: 200_000
)
expect(
    abs(persistentRank.windowScore - expectedPersistentScore) < 0.001
        && abs(persistentRank.appScore - expectedPersistentScore) < 0.001,
    "an older asynchronous selection must not replace newer persistent timestamps"
)

let sessionRank = orderingMemory.sessionRank(
    for: target,
    from: source,
    referenceTime: 200_000
)
expect(
    sessionRank.lastUsedAt == 200_000
        && sessionRank.interactionCount == 4,
    "an older asynchronous selection must not replace newer session or transition timestamps"
)

let migrationDefaults = isolatedDefaults("migration")
let legacyDocumentKey =
    "\(appKey)|Old title|axstandardwindow|document:file:///tmp/report.md"
let legacyFrameKey =
    "\(appKey)|Old title|axstandardwindow|frame:0,0,1440,900"
let legacyCursorWorkspaceKey =
    "com.todesktop.230313mzl4w4u92|axstandardwindow|workspace:altp"
let legacyChromeKey =
    "com.google.chrome|Old tab|axstandardwindow|identifier:chrome-window"
let legacyFallbackKey =
    "com.example.app|Example App|axapplicationfallback|identifier:window-server-fallback"
let legacyRecord = RecordFixture(
    selectionCount: 8,
    lastSelectedAt: 150_000,
    queryHits: ["report": 2],
    appSessionKey: nil
)
let legacySnapshot = SnapshotFixture(
    records: [
        legacyDocumentKey: legacyRecord,
        legacyFrameKey: legacyRecord,
        legacyCursorWorkspaceKey: legacyRecord,
        legacyChromeKey: legacyRecord,
        legacyFallbackKey: legacyRecord
    ],
    appRecords: [
        appKey: legacyRecord
    ]
)
migrationDefaults.set(
    try JSONEncoder().encode(legacySnapshot),
    forKey: "windowSelectionMemory.v3"
)

let migrationMemory = WindowSelectionMemory(defaults: migrationDefaults)
let migratedRank = migrationMemory.persistentRank(
    for: target,
    referenceTime: 150_000
)
expect(
    migratedRank.windowScore > 0 && migratedRank.appScore > 0,
    "reliable legacy document and application history must remain usable after migration"
)

guard let migratedData = migrationDefaults.data(
    forKey: "windowSelectionMemory.v4"
),
      let migratedSnapshot = try? JSONDecoder().decode(
        SnapshotFixture.self,
        from: migratedData
      ) else {
    fputs("FAIL: migration did not write a v4 snapshot\n", stderr)
    exit(1)
}
expect(
    Set(migratedSnapshot.records.keys) == Set([persistentKey]),
    "legacy frame, shared Cursor, Chrome, and synthetic fallback records must not consume v4 budget"
)
expect(
    Set(migratedSnapshot.appRecords.keys) == Set([appKey]),
    "application history must survive the window identity migration"
)

print("Window selection memory harness passed")
