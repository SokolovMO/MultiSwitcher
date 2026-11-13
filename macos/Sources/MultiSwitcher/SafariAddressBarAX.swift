import AppKit
import ApplicationServices
import CoreGraphics

/// Strict Accessibility adapter for Safari's own address/search field. It never
/// inspects page text fields, and it reports uncertainty instead of inviting a
/// keystroke-count fallback when Safari owns focus but AX cannot verify the bar.
@MainActor
enum SafariAddressBarAX {
    static let bundleIdentifier = "com.apple.Safari"
    private static let addressFieldIdentifier = "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"

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

    static func inspect() -> Detection {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier else {
            return .inactive
        }
        guard AXIsProcessTrusted() else { return .uncertain }

        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return .uncertain }
        let element = raw as! AXUIElement

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0,
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleIdentifier else {
            return .uncertain
        }

        func stringAttribute(_ name: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
                return nil
            }
            return value as? String
        }

        guard stringAttribute(kAXIdentifierAttribute as String) == addressFieldIdentifier else {
            return .inactive
        }
        guard let role = stringAttribute(kAXRoleAttribute as String),
              role == (kAXTextFieldRole as String) || role == "AXSearchField" else {
            return .uncertain
        }

        var valueRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRaw) == .success,
              let value = valueRaw as? String else { return .uncertain }
        var selectionRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                            &selectionRaw) == .success,
              let selectionRaw, CFGetTypeID(selectionRaw) == AXValueGetTypeID() else { return .uncertain }
        let selectionValue = selectionRaw as! AXValue
        guard AXValueGetType(selectionValue) == .cfRange else { return .uncertain }
        var range = CFRange()
        guard AXValueGetValue(selectionValue, .cfRange, &range), range.location >= 0, range.length >= 0,
              range.location + range.length <= (value as NSString).length else { return .uncertain }

        var valueSettable = DarwinBoolean(false)
        var rangeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable) == .success,
              valueSettable.boolValue,
              AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString,
                                             &rangeSettable) == .success,
              rangeSettable.boolValue else { return .uncertain }

        return .active(Field(element: element, processID: pid, identity: CFHash(element), value: value,
                             selection: NSRange(location: range.location, length: range.length)))
    }

    static func sameTarget(_ lhs: Field, _ rhs: Field) -> Bool {
        lhs.processID == rhs.processID && lhs.identity == rhs.identity
    }

    /// Rechecks focus, full value, and selection before writing; then verifies both
    /// the new value and caret. A failed transaction restores the captured snapshot.
    static func replace(target: Field, expectedValue: String, with replacement: String,
                        selection: NSRange) -> Bool {
        guard case .active(let current) = inspect(), sameTarget(target, current),
              current.value == expectedValue, current.selection == target.selection,
              selection.location >= 0, selection.length >= 0,
              NSMaxRange(selection) <= (replacement as NSString).length else { return false }

        guard AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString,
                                           replacement as CFString) == .success else { return false }
        var verifyRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target.element, kAXValueAttribute as CFString,
                                            &verifyRaw) == .success,
              (verifyRaw as? String) == replacement else {
            restore(target)
            return false
        }

        guard setSelection(target.element, selection) else {
            restore(target)
            return false
        }
        return true
    }

    private static func restore(_ target: Field) {
        _ = AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString,
                                         target.value as CFString)
        _ = setSelection(target.element, target.selection)
    }

    private static func setSelection(_ element: AXUIElement, _ range: NSRange) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }
}
