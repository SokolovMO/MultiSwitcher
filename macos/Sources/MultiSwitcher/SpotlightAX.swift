import AppKit
import ApplicationServices
import CoreGraphics
import MultiSwitcherCore

@MainActor
enum SpotlightAX {
    struct Field {
        let element: AXUIElement
        let processID: pid_t
        let identity: CFHashCode
        let value: String
        let selection: NSRange
    }

    enum Detection {
        case inactive
        case active(Field)
        case uncertain
    }

    /// Spotlight on recent macOS versions can keep the underlying app frontmost while
    /// SystemUIServer owns the focused search field. Use system-wide AX focus metadata
    /// to recognize that host; never fall through to synthetic Backspace when the system
    /// UI owns focus but does not expose a verifiable search field.
    static func inspect() -> Detection {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return .uncertain }
        let visibleWindows = windows.filter {
            (($0[kCGWindowAlpha as String] as? Double) ?? 0) > 0.15
        }
        let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let windowOwners = visibleWindows.compactMap { $0[kCGWindowOwnerName as String] as? String }
        let windowOwnerBundleIDs = visibleWindows.compactMap { window -> String? in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? NSNumber,
                  let app = NSRunningApplication(processIdentifier: pid_t(ownerPID.int32Value)) else {
                return nil
            }
            return app.bundleIdentifier
        }

        guard AXIsProcessTrusted() else { return .uncertain }
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, 0.15)
        var focusedRaw: AnyObject?
        let focusError = AXUIElementCopyAttributeValue(
            systemElement, kAXFocusedUIElementAttribute as CFString, &focusedRaw)
        let focusedElement = focusError == .success
            ? focusedRaw.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
            : nil

        var focusedPID: pid_t = 0
        if let focusedElement { _ = AXUIElementGetPid(focusedElement, &focusedPID) }
        let focusedBundleID = focusedPID > 0
            ? NSRunningApplication(processIdentifier: focusedPID)?.bundleIdentifier
            : nil
        var roleRaw: AnyObject?
        let role = focusedElement.flatMap { element -> String? in
            AXUIElementSetMessagingTimeout(element, 0.15)
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRaw) == .success else {
                return nil
            }
            return roleRaw as? String
        }

        let spotlightDetected = SpotlightTargetClassifier.isSpotlight(
            frontmostBundleIdentifier: frontmostID,
            windowOwnerNames: windowOwners,
            windowOwnerBundleIdentifiers: windowOwnerBundleIDs,
            focusedElementBundleIdentifier: focusedBundleID,
            focusedElementRole: role
        )
        if ["com.apple.systemuiserver", SpotlightTargetClassifier.campoBundleIdentifier]
            .contains(focusedBundleID ?? ""), !spotlightDetected {
            return .uncertain
        }
        guard spotlightDetected else { return .inactive }
        guard let field = focusedElement,
              focusedBundleID == SpotlightTargetClassifier.bundleIdentifier
                || focusedBundleID == "com.apple.systemuiserver"
                || focusedBundleID == SpotlightTargetClassifier.campoBundleIdentifier else { return .uncertain }

        guard let role,
              role == (kAXTextFieldRole as String) || role == "AXSearchField" else {
            return .uncertain
        }

        var valueRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &valueRaw) == .success,
              let value = valueRaw as? String else { return .uncertain }

        var selectionRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString,
                                            &selectionRaw) == .success,
              let selectionRaw,
              CFGetTypeID(selectionRaw) == AXValueGetTypeID() else { return .uncertain }
        let selectionValue = selectionRaw as! AXValue
        guard AXValueGetType(selectionValue) == .cfRange else { return .uncertain }
        var selection = CFRange()
        guard AXValueGetValue(selectionValue, .cfRange, &selection) else { return .uncertain }
        guard selection.location >= 0, selection.length >= 0,
              selection.location + selection.length <= (value as NSString).length else { return .uncertain }

        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else { return .uncertain }

        return .active(Field(
            element: field,
            processID: focusedPID,
            identity: CFHash(field),
            value: value,
            selection: NSRange(location: selection.location, length: selection.length)
        ))
    }

    static func isActive() -> Bool {
        if case .active = inspect() { return true }
        return false
    }

    static func sameTarget(_ lhs: Field, _ rhs: Field) -> Bool {
        lhs.processID == rhs.processID && lhs.identity == rhs.identity
    }

    /// Rechecks the live focus, original contents and target identity immediately before
    /// mutation. Sets the value through public Accessibility APIs and verifies readback.
    static func replace(
        target: Field,
        expectedValue: String,
        with replacement: String,
        selection: NSRange
    ) -> Bool {
        guard case .active(let current) = inspect(),
              sameTarget(target, current),
              expectedValue == target.value,
              snapshot(current) == snapshot(target),
              selection.location >= 0,
              selection.length >= 0,
              NSMaxRange(selection) <= (replacement as NSString).length else { return false }

        let error = AXUIElementSetAttributeValue(
            target.element, kAXValueAttribute as CFString, replacement as CFString)
        guard error == .success else { return false }

        var verifyRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(target.element, kAXValueAttribute as CFString,
                                            &verifyRaw) == .success,
              (verifyRaw as? String) == replacement else {
            _ = AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString,
                                             expectedValue as CFString)
            _ = setSelection(target.element, target.selection)
            return false
        }

        guard setSelection(target.element, selection) else {
            _ = AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString,
                                             expectedValue as CFString)
            _ = setSelection(target.element, target.selection)
            return false
        }
        return true
    }

    private static func setSelection(_ element: AXUIElement, _ range: NSRange) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString,
                                             &settable) == .success,
              settable.boolValue else { return false }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    private static func snapshot(_ field: Field) -> TextFieldEditSnapshot {
        TextFieldEditSnapshot(processID: field.processID, identity: UInt64(field.identity),
                              value: field.value, selection: field.selection)
    }
}
