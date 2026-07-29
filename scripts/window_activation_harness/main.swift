import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

var sequence = WindowActivationSequence()
let first = sequence.begin(initiatedAt: 100)
expect(sequence.isCurrent(first), "a newly started activation must be current")

let second = sequence.begin(initiatedAt: 101)
expect(!sequence.isCurrent(first), "a newer activation must supersede an older callback")
expect(sequence.isCurrent(second), "the latest activation must remain current")
expect(
    first.initiatedAt < second.initiatedAt,
    "activation requests must preserve the user action time instead of completion order"
)

let delayedFirstCompletion = [second, first]
let accepted = delayedFirstCompletion.filter(sequence.isCurrent)
expect(
    accepted == [second],
    "an older delayed callback must not be accepted after the newer selection"
)
expect(
    sequence.finishIfCurrent(second),
    "the latest activation must be allowed to complete once"
)
expect(
    !sequence.finishIfCurrent(second),
    "an activation completion must not be delivered more than once"
)

expect(
    WindowFocusLearningPolicy.allowsRecording(
        belongsToExpectedProcess: true,
        isMinimized: false,
        isSyntheticFallback: false,
        matchesFocusedAXWindow: true
    ),
    "an exact focused AX window must be eligible for learning"
)
expect(
    !WindowFocusLearningPolicy.allowsRecording(
        belongsToExpectedProcess: true,
        isMinimized: false,
        isSyntheticFallback: false,
        matchesFocusedAXWindow: false
    ),
    "a UI-only first-window fallback must not be eligible for learning"
)
expect(
    !WindowFocusLearningPolicy.allowsRecording(
        belongsToExpectedProcess: true,
        isMinimized: false,
        isSyntheticFallback: true,
        matchesFocusedAXWindow: true
    ),
    "a synthetic WindowServer fallback must not be eligible for learning"
)
expect(
    WindowActivationVerificationPolicy.verificationSource(
        requestedItemIsFallback: false
    ) == .requestedAXWindow,
    "a normal activation must verify the requested AX window without rebuilding the filtered catalog"
)
expect(
    WindowActivationVerificationPolicy.verificationSource(
        requestedItemIsFallback: true
    ) == .freshCatalogFallback,
    "a synthetic fallback must rebuild the catalog to bind the actual focused AX window"
)
expect(
    WindowActivationVerificationPolicy.acceptsDirectFocusedWindow(
        matchesRequestedWindow: true
    ),
    "a normal activation must accept the exact requested AX window"
)
expect(
    !WindowActivationVerificationPolicy.acceptsDirectFocusedWindow(
        matchesRequestedWindow: false
    ),
    "a normal selection must not succeed when a sibling window receives focus"
)
expect(
    WindowActivationRetryPolicy.shouldRetry(
        after: 0,
        verificationCount: 5
    ),
    "an early failed verification must allow another activation attempt"
)
expect(
    !WindowActivationRetryPolicy.shouldRetry(
        after: 4,
        verificationCount: 5
    ),
    "the last failed verification must not launch an unverified final activation attempt"
)

print("Window activation harness passed")
