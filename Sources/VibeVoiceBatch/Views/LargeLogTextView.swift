import AppKit
import SwiftUI

struct LargeLogTextView: NSViewRepresentable {
    var text: String
    var autoScrollToBottom = true

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
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.02, alpha: 1.0)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = true
        textView.backgroundColor = scrollView.backgroundColor
        textView.textColor = NSColor(calibratedRed: 0.62, green: 0.86, blue: 1.0, alpha: 1.0)
        textView.insertionPointColor = textView.textColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        updateNSView(scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        guard context.coordinator.lastText != text else { return }

        context.coordinator.lastText = text
        textView.string = text
        if autoScrollToBottom {
            textView.scrollRangeToVisible(NSRange(location: (textView.string as NSString).length, length: 0))
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var lastText = ""
    }
}
