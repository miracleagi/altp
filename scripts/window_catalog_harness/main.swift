import Foundation
import CoreGraphics

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let candidates = [
    WindowServerFallbackCandidate(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 30),
        layer: 0,
        alpha: 1,
        order: 0,
        isOnScreen: true
    ),
    WindowServerFallbackCandidate(
        frame: CGRect(x: 0, y: 30, width: 2560, height: 1410),
        layer: 0,
        alpha: 1,
        order: 3,
        isOnScreen: false
    ),
    WindowServerFallbackCandidate(
        frame: CGRect(x: 0, y: 30, width: 2560, height: 1410),
        layer: 0,
        alpha: 1,
        order: 7,
        isOnScreen: true
    ),
    WindowServerFallbackCandidate(
        frame: CGRect(x: 400, y: 1200, width: 84, height: 77),
        layer: 3,
        alpha: 1,
        order: 1,
        isOnScreen: true
    )
]

let preferred = WindowFallbackPolicy.preferredCandidate(from: candidates)
expect(preferred?.order == 7, "an on-screen real-sized window must be the preferred fallback")
expect(
    WindowFallbackPolicy.preferredCandidate(from: [candidates[0], candidates[3]]) == nil,
    "menu bars and small overlays must not create a fallback entry"
)
expect(
    WindowFallbackPolicy.kind(for: candidates[1]) == .crossSpaceWindowServer,
    "an off-screen WindowServer window must be recognized as cross-Space"
)
expect(
    WindowFallbackPolicy.shouldCreateApplicationFallback(
        hasDiscoverableAXWindow: false,
        isHidden: false,
        isTerminated: false,
        candidate: candidates[1]
    ),
    "a running visible app with only a WindowServer window must receive a fallback"
)
expect(
    !WindowFallbackPolicy.shouldCreateApplicationFallback(
        hasDiscoverableAXWindow: true,
        isHidden: false,
        isTerminated: false,
        candidate: candidates[1]
    ),
    "a real AX window must always suppress the application fallback"
)
expect(
    !WindowFallbackPolicy.shouldCreateApplicationFallback(
        hasDiscoverableAXWindow: false,
        isHidden: true,
        isTerminated: false,
        candidate: candidates[1]
    ),
    "a hidden app must not receive a WindowServer fallback"
)

let mainWindowPriority = WindowFallbackPolicy.activationPriority(
    title: "Example App",
    appName: "Example App",
    subrole: "AXStandardWindow",
    isMain: true,
    isFocused: true
)
let secondaryWindowPriority = WindowFallbackPolicy.activationPriority(
    title: "Document",
    appName: "Example App",
    subrole: "AXStandardWindow",
    isMain: false,
    isFocused: false
)
expect(
    mainWindowPriority > secondaryWindowPriority,
    "the generic main window must win delayed activation"
)

expect(
    WindowCompatibilityRules.shouldExcludeWindow(
        appName: "飞书",
        bundleIdentifier: "com.electron.lark",
        title: "WatermarkWidget"
    ),
    "the verified Feishu watermark must stay isolated in compatibility rules"
)
expect(
    !WindowCompatibilityRules.shouldExcludeWindow(
        appName: "Example App",
        bundleIdentifier: "com.example.app",
        title: "WatermarkWidget"
    ),
    "a similarly named window from another app must not be globally hidden"
)
expect(
    !WindowCompatibilityRules.shouldExcludeWindow(
        appName: "Lark",
        bundleIdentifier: "com.example.lark",
        title: "WatermarkWidget"
    ),
    "a non-Feishu app with a similar localized name must not match compatibility rules"
)
expect(
    WindowCompatibilityRules.shouldExcludeWindow(
        appName: "飞书",
        bundleIdentifier: "com.electron.lark",
        title: ""
    ),
    "the verified untitled Feishu auxiliary must stay isolated in compatibility rules"
)
expect(
    !WindowCompatibilityRules.shouldExcludeWindow(
        appName: "飞书",
        bundleIdentifier: "com.electron.lark",
        title: "飞书"
    ),
    "the real titled Feishu window must remain visible"
)
expect(
    WindowCompatibilityRules.deduplicationKey(
        appName: "飞书会议",
        bundleIdentifier: "com.electron.lark.iron",
        processIdentifier: 123
    ) != nil,
    "the verified meeting helper must keep its narrow deduplication rule"
)
expect(
    !WindowCompatibilityRules.allowsApplicationFallback(
        appName: "飞书会议",
        bundleIdentifier: "com.electron.lark.iron"
    ),
    "a verified auxiliary process must not be restored by the generic fallback"
)
expect(
    WindowCompatibilityRules.allowsApplicationFallback(
        appName: "Example App",
        bundleIdentifier: "com.example.app"
    ),
    "unrecognized apps must remain eligible for the generic fallback"
)
expect(
    WindowCompatibilityRules.deduplicationKey(
        appName: "Example App",
        bundleIdentifier: "com.example.app",
        processIdentifier: 123
    ) == nil,
    "unrecognized apps must never receive compatibility deduplication"
)

print("Window catalog harness passed")
