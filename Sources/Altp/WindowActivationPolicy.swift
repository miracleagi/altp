import Foundation

struct WindowActivationRequest: Equatable {
    let generation: UInt64
    let initiatedAt: TimeInterval
}

struct WindowActivationSequence {
    private(set) var currentGeneration: UInt64 = 0

    mutating func begin(initiatedAt: TimeInterval) -> WindowActivationRequest {
        currentGeneration &+= 1
        return WindowActivationRequest(
            generation: currentGeneration,
            initiatedAt: initiatedAt
        )
    }

    func isCurrent(_ request: WindowActivationRequest) -> Bool {
        request.generation == currentGeneration
    }

    mutating func finishIfCurrent(_ request: WindowActivationRequest) -> Bool {
        guard isCurrent(request) else {
            return false
        }
        currentGeneration &+= 1
        return true
    }
}

enum WindowFocusLearningPolicy {
    static func allowsRecording(
        belongsToExpectedProcess: Bool,
        isMinimized: Bool,
        isSyntheticFallback: Bool,
        matchesFocusedAXWindow: Bool
    ) -> Bool {
        belongsToExpectedProcess
            && !isMinimized
            && !isSyntheticFallback
            && matchesFocusedAXWindow
    }
}

enum WindowActivationVerificationSource: Equatable {
    case requestedAXWindow
    case freshCatalogFallback
}

enum WindowActivationVerificationPolicy {
    static func verificationSource(
        requestedItemIsFallback: Bool
    ) -> WindowActivationVerificationSource {
        requestedItemIsFallback
            ? .freshCatalogFallback
            : .requestedAXWindow
    }

    static func acceptsDirectFocusedWindow(
        matchesRequestedWindow: Bool
    ) -> Bool {
        matchesRequestedWindow
    }
}

enum WindowActivationRetryPolicy {
    static func shouldRetry(
        after attemptIndex: Int,
        verificationCount: Int
    ) -> Bool {
        attemptIndex >= 0
            && verificationCount > 0
            && attemptIndex + 1 < verificationCount
    }
}
