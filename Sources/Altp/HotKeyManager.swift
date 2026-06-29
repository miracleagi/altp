import Carbon
import Foundation

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    return manager.performAction(for: event) ? noErr : OSStatus(eventNotHandledErr)
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
    private let hotKeyID: EventHotKeyID
    private let action: () -> Void

    init(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
        self.hotKeyID = EventHotKeyID(
            signature: fourCharacterCode("ALTP"),
            id: id
        )
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

        let registrationID = self.hotKeyID
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            registrationID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
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

    fileprivate func performAction(for event: EventRef) -> Bool {
        var eventHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyID
        )

        guard status == noErr,
              eventHotKeyID.signature == hotKeyID.signature,
              eventHotKeyID.id == hotKeyID.id else {
            return false
        }

        action()
        return true
    }
}

private func fourCharacterCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
