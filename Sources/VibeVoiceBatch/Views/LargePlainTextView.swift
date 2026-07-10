import AppKit
import SwiftUI

struct LargePlainTextView: NSViewRepresentable {
    enum TextStyle {
        case document
        case metadata
    }

    var text: String
    var placeholder: String
    var style: TextStyle = .document
    var telemetryKind: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.72)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textColor = NSColor.labelColor
        textView.font = font
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        scrollView.documentView = textView
        context.coordinator.textView = textView
        updateNSView(scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let displayText = text.isEmpty ? placeholder : text
        guard context.coordinator.lastText != displayText else { return }

        context.coordinator.lastText = displayText
        textView.font = font
        textView.string = displayText
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))

        if let telemetryKind {
            FonimTelemetry.largeTextUpdated(kind: telemetryKind, characterCount: displayText.count)
        }
    }

    private var font: NSFont {
        switch style {
        case .document:
            NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        case .metadata:
            NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var lastText = ""
    }
}
