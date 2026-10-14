import SwiftUI
import AppKit
import TaskTickCore

struct ScriptEditorView: View {
    @Binding var scriptBody: String
    var parameters: [RunParameter] = []
    var insertion: ScriptEditorInsertion? = nil
    @State private var showExpandedEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let insertion, !parameters.isEmpty {
                HStack {
                    Spacer()
                    variableMenu(parameters: parameters, insertion: insertion, text: $scriptBody)
                }
            }
            ZStack(alignment: .topTrailing) {
                CodeTextEditor(text: $scriptBody, insertion: insertion)
                    .frame(minHeight: 140, maxHeight: 280)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

                Button {
                    showExpandedEditor = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .padding(8)
                .pointerCursor()
                .help(L10n.tr("editor.script.expand"))
            }

            Text(L10n.tr("editor.script.placeholder"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .sheet(isPresented: $showExpandedEditor) {
            ExpandedScriptEditor(scriptBody: $scriptBody, parameters: parameters, insertion: insertion)
        }
    }
}

// MARK: - Expanded Editor

struct ExpandedScriptEditor: View {
    @Binding var scriptBody: String
    var parameters: [RunParameter] = []
    var insertion: ScriptEditorInsertion? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("editor.section.script"))
                    .font(.headline)
                Spacer()
                if let insertion, !parameters.isEmpty {
                    variableMenu(parameters: parameters, insertion: insertion, text: $scriptBody)
                }
                Button(L10n.tr("editor.script.collapse")) {
                    dismiss()
                }
                .pointerCursor()
            }
            .padding()

            Divider()

            CodeTextEditor(text: $scriptBody, insertion: insertion, isExpanded: true)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .padding(8)
        }
        .frame(width: 680, height: 480)
    }
}

@MainActor
private func variableMenu(parameters: [RunParameter], insertion: ScriptEditorInsertion, text: Binding<String>) -> some View {
    Menu {
        ForEach(parameters) { parameter in
            Button("\(parameter.name) · ${\(parameter.variableName)}") {
                insertion.insertVariable(parameter.variableName, into: text)
            }
        }
    } label: {
        Label(L10n.tr("run_parameters.insert_variable"), systemImage: "text.insert")
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .pointerCursor()
}

/// Keeps the script caret available while the user edits the parameter fields.
@MainActor
final class ScriptEditorInsertion {
    weak var textView: NSTextView?
    weak var expandedTextView: NSTextView?
    var selectedRange = NSRange(location: NSNotFound, length: 0)

    func insertVariable(_ name: String, into text: Binding<String>) {
        guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { return }
        let reference = "\"${\(name)}\""
        let editor = expandedTextView?.window?.isVisible == true ? expandedTextView : textView
        let source = text.wrappedValue as NSString
        let selection = selectedRange.location == NSNotFound ? editor?.selectedRange() ?? selectedRange : selectedRange
        let location = selection.location == NSNotFound ? source.length : min(selection.location, source.length)
        let range = NSRange(location: location, length: min(selection.length, source.length - location))
        if let editor, let window = editor.window, editor.string == text.wrappedValue {
            window.makeFirstResponder(editor)
            editor.insertText(reference, replacementRange: range)
            editor.scrollRangeToVisible(editor.selectedRange())
            selectedRange = editor.selectedRange()
        } else {
            // A scrolled-out Form row may no longer have a native text view.
            text.wrappedValue = source.replacingCharacters(in: range, with: reference)
            selectedRange = NSRange(location: location + (reference as NSString).length, length: 0)
        }
    }
}

// MARK: - NSTextView Wrapper

struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var insertion: ScriptEditorInsertion? = nil
    var isExpanded = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, insertion: insertion)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = TabSupportingTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView
        if isExpanded {
            insertion?.expandedTextView = textView
        } else {
            insertion?.textView = textView
        }

        textView.string = text
        restoreSelection(in: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        if textView.string != text {
            let selectedRange = insertion?.selectedRange ?? textView.selectedRange()
            textView.string = text
            restoreSelection(in: textView, range: selectedRange)
        }
    }

    private func restoreSelection(in textView: NSTextView, range: NSRange? = nil) {
        let range = range ?? insertion?.selectedRange ?? NSRange(location: NSNotFound, length: 0)
        let length = (textView.string as NSString).length
        let location = range.location == NSNotFound ? length : min(range.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(range.length, length - location)))
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?
        let insertion: ScriptEditorInsertion?

        init(text: Binding<String>, insertion: ScriptEditorInsertion?) {
            self.text = text
            self.insertion = insertion
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  textView.window?.firstResponder === textView else { return }
            insertion?.selectedRange = textView.selectedRange()
        }
    }
}

// MARK: - Tab Supporting TextView

class TabSupportingTextView: NSTextView {
    override func insertTab(_ sender: Any?) {
        insertText("  ", replacementRange: selectedRange())
    }

    override func insertNewline(_ sender: Any?) {
        // Auto-indent: match previous line's leading whitespace
        let currentLine = getCurrentLineContent()
        let indent = currentLine.prefix(while: { $0 == " " || $0 == "\t" })
        super.insertNewline(sender)
        if !indent.isEmpty {
            insertText(String(indent), replacementRange: selectedRange())
        }
    }

    private func getCurrentLineContent() -> String {
        guard let textStorage = textStorage else { return "" }
        let text = textStorage.string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        return text.substring(with: lineRange)
    }
}
