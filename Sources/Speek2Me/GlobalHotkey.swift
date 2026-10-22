import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut through Carbon's RegisterEventHotKey. Unlike an event tap it
/// needs no Accessibility permission, and it reaches a menu-bar app that has no window.
final class GlobalHotkey {
    /// ⌃⌥⌘M: pause and resume announcements.
    static let pauseKeyCode = UInt32(kVK_ANSI_M)
    static let pauseModifiers = UInt32(cmdKey | optionKey | controlKey)
    static let pauseDescription = "⌃⌥⌘M"

    private static var registry: [UInt32: GlobalHotkey] = [:]
    private static var nextID: UInt32 = 1
    private static let signature = OSType(0x53504B32) // "SPK2"

    private let id: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // The C callback cannot capture Swift context; it looks the instance up by id.
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            GlobalHotkey.registry[hotKeyID.id]?.action()
            return noErr
        }, 1, &eventType, nil, &handlerRef)
        guard installed == noErr else { return nil }
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
        Self.registry[id] = self
    }

    deinit {
        unregister()
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        Self.registry[id] = nil
    }
}
