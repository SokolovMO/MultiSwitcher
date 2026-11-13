import Foundation

/// Identifies the exact editable field state observed before a replacement.
/// Any text, focus target, or selection change invalidates the pending edit.
public struct TextFieldEditSnapshot: Equatable {
    public let processID: Int32
    public let identity: UInt64
    public let value: String
    public let selection: NSRange

    public init(processID: Int32, identity: UInt64, value: String, selection: NSRange) {
        self.processID = processID
        self.identity = identity
        self.value = value
        self.selection = selection
    }
}
