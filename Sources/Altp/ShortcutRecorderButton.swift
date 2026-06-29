import AppKit
import Carbon.HIToolbox

final class ShortcutRecorderButton: NSButton {
    var onShortcutChange: ((KeyboardShortcut) -> Void)?

    var shortcut: KeyboardShortcut {
        didSet {
            updateTitle()
        }
    }

    private var isRecording = false

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        title = shortcut.displayString
        bezelStyle = .rounded
        controlSize = .large
        target = self
        action = #selector(beginRecording)
        setContentHuggingPriority(.required, for: .horizontal)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let keyCode = UInt32(event.keyCode)
        let modifiers = KeyboardShortcut.carbonModifiers(from: event.modifierFlags)

        guard KeyboardShortcut.isAllowed(keyCode: keyCode, modifiers: modifiers) else {
            NSSound.beep()
            title = "Add a modifier"
            return
        }

        shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
        onShortcutChange?(shortcut)
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            stopRecording()
        }
        return result
    }

    @objc private func beginRecording() {
        isRecording = true
        title = "Type shortcut"
        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        isRecording = false
        updateTitle()
    }

    private func updateTitle() {
        title = shortcut.displayString
    }
}
