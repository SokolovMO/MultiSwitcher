import Foundation

/// Exact, whole-value undo state for fields where keystroke-based replacement is unsafe.
public struct ExactTextUndoState: Equatable {
    public struct Step: Equatable {
        public let text: String
        public let selection: NSRange
        public let isConverted: Bool

        public init(text: String, selection: NSRange, isConverted: Bool) {
            self.text = text
            self.selection = selection
            self.isConverted = isConverted
        }
    }

    public let originalText: String
    public let convertedText: String
    public let originalSelection: NSRange
    public let convertedSelection: NSRange
    public private(set) var isConverted: Bool

    public init(originalText: String, convertedText: String,
                originalSelection: NSRange, convertedSelection: NSRange,
                isConverted: Bool = true) {
        self.originalText = originalText
        self.convertedText = convertedText
        self.originalSelection = originalSelection
        self.convertedSelection = convertedSelection
        self.isConverted = isConverted
    }

    /// Toggles only when the live field still exactly matches the last known value.
    /// Any user edit invalidates this undo pair instead of risking replacement of newer text.
    public mutating func toggle(currentText: String, currentSelection: NSRange? = nil) -> Step? {
        let selectionMatchesCurrentState = currentSelection.map {
            $0 == (isConverted ? convertedSelection : originalSelection)
        } ?? true
        guard selectionMatchesCurrentState else { return nil }

        if isConverted, currentText == convertedText {
            isConverted = false
            return Step(text: originalText, selection: originalSelection, isConverted: false)
        }
        if !isConverted, currentText == originalText {
            isConverted = true
            return Step(text: convertedText, selection: convertedSelection, isConverted: true)
        }
        return nil
    }
}
