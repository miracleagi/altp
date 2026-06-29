import Carbon
import Foundation

private let hotKeyEventHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else {
        return noErr
    }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.performAction()
    return noErr
}

final class HotKeyManager {
    enum RegistrationError: Error, CustomStringConvertible {
        case eventHandler(OSStatus)
        case hotKey(OSStatus)

        var description: String {
            switch self {
            case .eventHandler(let status):
                return "InstallEventHandler failed with status \(status)"
            case .hotKey(let status):
                return "RegisterEventHotKey failed with status \(status)"
            }
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
        self.action = action

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            throw RegistrationError.eventHandler(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(
            signature: fourCharacterCode("ALTP"),
            id: 1
        )

        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            throw RegistrationError.hotKey(hotKeyStatus)
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    fileprivate func performAction() {
        action()
    }
}

private func fourCharacterCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
