import SwiftUI
import AppKit
import IntermezzoKit

/// A plain-text AppleScript editor with syntax colouring. Smart quotes and dashes are off:
/// curly quotes would break the script.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.font = Self.font
        view.textColor = Self.plain
        view.insertionPointColor = .white
        view.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        view.drawsBackground = true
        view.textContainerInset = NSSize(width: 6, height: 8)
        view.string = text
        Self.highlight(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        // Changed from outside (a settings field): keep the caret where it was.
        let selection = view.selectedRanges
        view.string = text
        Self.highlight(view)
        let length = (text as NSString).length
        view.selectedRanges = selection.map { value in
            let r = value.rangeValue
            return NSValue(range: NSRange(location: min(r.location, length), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            CodeEditor.highlight(view)
            parent.text = view.string
        }
    }

    // MARK: Colouring

    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let plain = NSColor(white: 0.92, alpha: 1)

    private static func color(_ kind: AppleScriptTokenKind) -> NSColor {
        switch kind {
        case .comment: return NSColor(white: 0.55, alpha: 1)
        case .string: return NSColor(red: 0.99, green: 0.56, blue: 0.43, alpha: 1)
        case .number: return NSColor(red: 0.85, green: 0.79, blue: 0.47, alpha: 1)
        case .keyword: return NSColor(red: 0.99, green: 0.37, blue: 0.64, alpha: 1)
        }
    }

    static func highlight(_ view: NSTextView) {
        guard let storage = view.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: plain], range: all)
        for token in AppleScriptTokens.scan(storage.string) where NSMaxRange(token.range) <= storage.length {
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color(token.kind)]
            if token.kind == .keyword {
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            }
            storage.addAttributes(attrs, range: token.range)
        }
        storage.endEditing()
        view.typingAttributes = [.font: font, .foregroundColor: plain]
    }
}
