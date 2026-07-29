import Foundation

enum WindowIdentityPolicy {
    private static let persistentKeyVersion = "window-identity:v1"
    private static let persistentKeyPrefix = "\(persistentKeyVersion)|"

    static func applicationKey(
        bundleIdentifier: String?,
        appName: String
    ) -> String {
        normalizedStructuralValue(bundleIdentifier ?? appName)
    }

    static func persistentWindowKey(
        applicationKey: String,
        appName: String,
        bundleIdentifier: String?,
        title: String,
        subrole: String,
        document: String,
        identifier: String
    ) -> String? {
        if isChrome(appName: appName, bundleIdentifier: bundleIdentifier) {
            return nil
        }

        let normalizedSubrole = normalizedStructuralValue(subrole)
        let normalizedIdentifier = normalizedIdentityValue(identifier)
        guard normalizedSubrole != "axapplicationfallback",
              normalizedStructuralValue(normalizedIdentifier)
                != "window-server-fallback" else {
            return nil
        }

        if isCursor(appName: appName, bundleIdentifier: bundleIdentifier) {
            if let workspace = cursorWorkspace(from: title) {
                return makePersistentKey(
                    applicationKey: applicationKey,
                    subrole: normalizedSubrole,
                    kind: "cursor-workspace",
                    identity: workspace
                )
            }

            guard !normalizedIdentifier.isEmpty else {
                return nil
            }
            return makePersistentKey(
                applicationKey: applicationKey,
                subrole: normalizedSubrole,
                kind: "identifier",
                identity: normalizedIdentifier
            )
        }

        let normalizedDocument = normalizedIdentityValue(document)
        if !normalizedDocument.isEmpty {
            return makePersistentKey(
                applicationKey: applicationKey,
                subrole: normalizedSubrole,
                kind: "document",
                identity: normalizedDocument
            )
        }

        guard !normalizedIdentifier.isEmpty else {
            return nil
        }
        return makePersistentKey(
            applicationKey: applicationKey,
            subrole: normalizedSubrole,
            kind: "identifier",
            identity: normalizedIdentifier
        )
    }

    static func applicationSessionKey(
        applicationKey: String,
        processIdentifier: Int32,
        launchTime: TimeInterval?
    ) -> String {
        let launchIdentity: String
        if let launchTime, launchTime.isFinite {
            launchIdentity = String(
                Int64((launchTime * 1_000_000).rounded())
            )
        } else {
            launchIdentity = "unknown"
        }

        return [
            "app-session:v2",
            encoded(applicationKey),
            "pid:\(processIdentifier)",
            "launch:\(launchIdentity)"
        ]
        .joined(separator: "|")
    }

    static func ambiguousPersistentKeys(
        in keys: [String?]
    ) -> Set<String> {
        var counts: [String: Int] = [:]
        for key in keys.compactMap({ $0 }) {
            counts[key, default: 0] += 1
        }
        return Set(
            counts.compactMap { key, count in
                count > 1 ? key : nil
            }
        )
    }

    static func isCurrentPersistentKey(_ key: String) -> Bool {
        key.hasPrefix(persistentKeyPrefix)
    }

    static func migratedLegacyPersistentKey(_ legacyKey: String) -> String? {
        if isCurrentPersistentKey(legacyKey) {
            return legacyKey
        }

        let parts = legacyKey.components(separatedBy: "|")
        guard parts.count >= 3,
              let applicationKey = parts.first,
              !applicationKey.isEmpty,
              let hint = parts.last else {
            return nil
        }

        if isChromeApplicationKey(applicationKey) {
            return nil
        }

        let isCursor = isCursorApplicationKey(applicationKey)
        let subrole: String
        if parts.count == 3, isCursor {
            subrole = parts[1]
        } else {
            guard parts.count >= 4 else {
                return nil
            }
            subrole = parts[parts.count - 2]
        }

        if hint.hasPrefix("frame:") || hint.hasPrefix("workspace:") {
            return nil
        }

        if hint.hasPrefix("document:") {
            guard !isCursor else {
                return nil
            }
            let identity = String(hint.dropFirst("document:".count))
            guard !identity.isEmpty else {
                return nil
            }
            return makePersistentKey(
                applicationKey: applicationKey,
                subrole: subrole,
                kind: "document",
                identity: identity
            )
        }

        if hint.hasPrefix("identifier:") {
            let identity = String(hint.dropFirst("identifier:".count))
            guard !identity.isEmpty,
                  normalizedStructuralValue(subrole) != "axapplicationfallback",
                  normalizedStructuralValue(identity) != "window-server-fallback" else {
                return nil
            }
            return makePersistentKey(
                applicationKey: applicationKey,
                subrole: subrole,
                kind: "identifier",
                identity: identity
            )
        }

        return nil
    }

    private static func makePersistentKey(
        applicationKey: String,
        subrole: String,
        kind: String,
        identity: String
    ) -> String {
        [
            persistentKeyVersion,
            encoded(normalizedStructuralValue(applicationKey)),
            encoded(normalizedStructuralValue(subrole)),
            kind,
            encoded(normalizedIdentityValue(identity))
        ]
        .joined(separator: "|")
    }

    private static func cursorWorkspace(from title: String) -> String? {
        guard let separatorRange = title.range(
            of: " — ",
            options: .backwards
        ) else {
            return nil
        }

        let workspace = normalizedIdentityValue(
            String(title[separatorRange.upperBound...])
        )
        return workspace.isEmpty ? nil : workspace
    }

    private static func isCursor(
        appName: String,
        bundleIdentifier: String?
    ) -> Bool {
        bundleIdentifier.map {
            normalizedStructuralValue($0) == "com.todesktop.230313mzl4w4u92"
        } == true || normalizedStructuralValue(appName) == "cursor"
    }

    private static func isChrome(
        appName: String,
        bundleIdentifier: String?
    ) -> Bool {
        bundleIdentifier.map {
            normalizedStructuralValue($0).hasPrefix("com.google.chrome")
        } == true || normalizedStructuralValue(appName) == "google chrome"
    }

    private static func isCursorApplicationKey(_ applicationKey: String) -> Bool {
        let normalizedKey = normalizedStructuralValue(applicationKey)
        return normalizedKey == "com.todesktop.230313mzl4w4u92"
            || normalizedKey == "cursor"
    }

    private static func isChromeApplicationKey(_ applicationKey: String) -> Bool {
        let normalizedKey = normalizedStructuralValue(applicationKey)
        return normalizedKey.hasPrefix("com.google.chrome")
            || normalizedKey == "google chrome"
    }

    private static func encoded(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private static func normalizedStructuralValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func normalizedIdentityValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
