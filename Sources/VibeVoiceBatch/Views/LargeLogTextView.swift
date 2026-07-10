import AppKit
import SwiftUI

struct LargeLogTextView: NSViewRepresentable {
    var text: String
    var autoScrollToBottom = true
    var scrollToBottomTrigger = ""

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
        scrollView.contentView.postsBoundsChangedNotifications = true

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
        context.coordinator.startObserving(scrollView: scrollView)
        updateNSView(scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let didChangeText = context.coordinator.lastText != text
        let didChangeTrigger = context.coordinator.lastScrollToBottomTrigger != scrollToBottomTrigger
        guard didChangeText || didChangeTrigger else { return }

        let shouldScrollToBottom = autoScrollToBottom && (context.coordinator.isFollowingTail || didChangeTrigger)
        context.coordinator.lastScrollToBottomTrigger = scrollToBottomTrigger
        if didChangeText {
            context.coordinator.lastText = text
            textView.string = text
        }

        if shouldScrollToBottom {
            context.coordinator.scrollToBottom()
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var lastText = ""
        var lastScrollToBottomTrigger = ""
        var isFollowingTail = true
        private var scrollObserver: NSObjectProtocol?
        private var isProgrammaticScroll = false

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }

        func startObserving(scrollView: NSScrollView) {
            guard scrollObserver == nil else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView, !self.isProgrammaticScroll else { return }
                self.isFollowingTail = self.isNearBottom(scrollView)
            }
        }

        func scrollToBottom() {
            guard let textView else { return }
            isProgrammaticScroll = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                textView.scrollRangeToVisible(NSRange(location: (textView.string as NSString).length, length: 0))
                self.isFollowingTail = true
                self.isProgrammaticScroll = false
            }
        }

        private func isNearBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let visibleRect = scrollView.contentView.bounds
            let distanceFromBottom = documentView.bounds.maxY - visibleRect.maxY
            return distanceFromBottom < 28
        }
    }
}
