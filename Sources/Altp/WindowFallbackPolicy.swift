import Foundation
import CoreGraphics

struct WindowServerFallbackCandidate {
    let frame: CGRect
    let layer: Int
    let alpha: Double
    let order: Int
    let isOnScreen: Bool
}

enum WindowFallbackKind: Equatable {
    case onScreenWindowServer
    case crossSpaceWindowServer
}

enum WindowFallbackPolicy {
    static func preferredCandidate(
        from candidates: [WindowServerFallbackCandidate]
    ) -> WindowServerFallbackCandidate? {
        candidates
            .filter { (candidate: WindowServerFallbackCandidate) -> Bool in
                candidate.layer == 0 &&
                    candidate.alpha > 0 &&
                    candidate.frame.size.width >= 240 &&
                    candidate.frame.size.height >= 160
            }
            .max { (lhs: WindowServerFallbackCandidate, rhs: WindowServerFallbackCandidate) -> Bool in
                if lhs.isOnScreen != rhs.isOnScreen {
                    return !lhs.isOnScreen
                }

                let lhsArea = lhs.frame.size.width * lhs.frame.size.height
                let rhsArea = rhs.frame.size.width * rhs.frame.size.height
                if lhsArea != rhsArea {
                    return lhsArea < rhsArea
                }
                return lhs.order > rhs.order
            }
    }

    static func shouldCreateApplicationFallback(
        hasDiscoverableAXWindow: Bool,
        isHidden: Bool,
        isTerminated: Bool,
        candidate: WindowServerFallbackCandidate?
    ) -> Bool {
        !hasDiscoverableAXWindow &&
            !isHidden &&
            !isTerminated &&
            candidate != nil
    }

    static func kind(for candidate: WindowServerFallbackCandidate) -> WindowFallbackKind {
        candidate.isOnScreen ? .onScreenWindowServer : .crossSpaceWindowServer
    }

    static func activationPriority(
        title: String,
        appName: String,
        subrole: String,
        isMain: Bool,
        isFocused: Bool
    ) -> Int {
        let normalizedTitle = normalized(title)
        var priority = 0

        if !normalizedTitle.isEmpty {
            priority += 50
        }
        if normalizedTitle == normalized(appName) {
            priority += 200
        }
        if normalized(subrole) == "axstandardwindow" {
            priority += 300
        }
        if isMain {
            priority += 200
        }
        if isFocused {
            priority += 100
        }
        return priority
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .joined(separator: " ")
    }
}
