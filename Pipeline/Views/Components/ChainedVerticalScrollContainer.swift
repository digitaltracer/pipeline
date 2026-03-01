import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ChainedVerticalScrollContainer<Content: View>: View {
    let height: CGFloat
    let showsIndicators: Bool
    private let content: Content

    init(
        height: CGFloat,
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.height = height
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        platformView
            .frame(height: height)
            .clipped()
    }

    @ViewBuilder
    private var platformView: some View {
        #if os(macOS)
        ChainedNSScrollViewRepresentable(
            showsIndicators: showsIndicators,
            content: content
        )
        #else
        ChainedUIScrollViewRepresentable(
            showsIndicators: showsIndicators,
            content: content
        )
        #endif
    }
}

#if os(macOS)
private struct ChainedNSScrollViewRepresentable<Content: View>: NSViewRepresentable {
    let showsIndicators: Bool
    let content: Content

    func makeNSView(context: Context) -> ChainedNSScrollContainerView<Content> {
        ChainedNSScrollContainerView(
            content: content,
            showsIndicators: showsIndicators
        )
    }

    func updateNSView(_ nsView: ChainedNSScrollContainerView<Content>, context: Context) {
        nsView.update(content: content, showsIndicators: showsIndicators)
    }
}

private final class ChainedNSScrollContainerView<Content: View>: NSView {
    private let scrollView = ChainedNSScrollView()
    private let documentView: FlippedDocumentContainerView<Content>

    init(content: Content, showsIndicators: Bool) {
        self.documentView = FlippedDocumentContainerView(content: content)
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = showsIndicators
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = !showsIndicators

        scrollView.documentView = documentView
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        updateDocumentLayout()
    }

    func update(content: Content, showsIndicators: Bool) {
        documentView.hostingView.rootView = content
        scrollView.hasVerticalScroller = showsIndicators
        scrollView.autohidesScrollers = !showsIndicators
        updateDocumentLayout()
    }

    private func updateDocumentLayout() {
        let viewportWidth = max(scrollView.contentSize.width, 1)
        documentView.frame.size.width = viewportWidth
        documentView.hostingView.frame.size.width = viewportWidth

        documentView.hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = max(documentView.hostingView.fittingSize.height, 1)
        documentView.hostingView.frame.size.height = fittingHeight
        documentView.frame.size.height = fittingHeight
    }
}

private final class ChainedNSScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let previousOffset = contentView.bounds.origin.y
        super.scrollWheel(with: event)
        let updatedOffset = contentView.bounds.origin.y

        let consumedVertical = abs(updatedOffset - previousOffset) > 0.5
        guard !consumedVertical, abs(event.scrollingDeltaY) > 0 else {
            return
        }

        nearestAncestorScrollView()?.scrollWheel(with: event)
    }

    private func nearestAncestorScrollView() -> NSScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? NSScrollView, scrollView !== self {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}

private final class FlippedDocumentContainerView<Content: View>: NSView {
    let hostingView: NSHostingView<Content>

    init(content: Content) {
        self.hostingView = NSHostingView(rootView: content)
        super.init(frame: .zero)
        addSubview(hostingView)
        hostingView.frame = .zero
        hostingView.autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
}
#else
private struct ChainedUIScrollViewRepresentable<Content: View>: UIViewRepresentable {
    let showsIndicators: Bool
    let content: Content

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    func makeUIView(context: Context) -> ChainedUIScrollView {
        let scrollView = ChainedUIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = showsIndicators
        scrollView.showsHorizontalScrollIndicator = false

        let hostedView = context.coordinator.hostingController.view
        hostedView?.backgroundColor = .clear
        hostedView?.translatesAutoresizingMaskIntoConstraints = false

        if let hostedView {
            scrollView.addSubview(hostedView)
            NSLayoutConstraint.activate([
                hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
            ])
        }

        context.coordinator.refreshOuterScrollView(for: scrollView)
        return scrollView
    }

    func updateUIView(_ uiView: ChainedUIScrollView, context: Context) {
        uiView.showsVerticalScrollIndicator = showsIndicators
        context.coordinator.hostingController.rootView = content
        context.coordinator.refreshOuterScrollView(for: uiView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let hostingController: UIHostingController<Content>

        init(content: Content) {
            self.hostingController = UIHostingController(rootView: content)
        }

        func refreshOuterScrollView(for scrollView: ChainedUIScrollView) {
            DispatchQueue.main.async { [weak scrollView] in
                guard let scrollView else { return }
                scrollView.outerScrollView = Self.findAncestorScrollView(
                    from: scrollView.superview,
                    excluding: scrollView
                )
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard
                let innerScrollView = scrollView as? ChainedUIScrollView,
                let outerScrollView = innerScrollView.outerScrollView,
                !innerScrollView.isForwardingOffset
            else {
                return
            }

            let innerTop = -innerScrollView.adjustedContentInset.top
            let innerBottom = max(
                innerTop,
                innerScrollView.contentSize.height
                    - innerScrollView.bounds.height
                    + innerScrollView.adjustedContentInset.bottom
            )

            let offsetY = innerScrollView.contentOffset.y
            let overflow: CGFloat
            let clampedY: CGFloat

            if offsetY < innerTop {
                overflow = offsetY - innerTop
                clampedY = innerTop
            } else if offsetY > innerBottom {
                overflow = offsetY - innerBottom
                clampedY = innerBottom
            } else {
                return
            }

            innerScrollView.isForwardingOffset = true
            innerScrollView.contentOffset.y = clampedY

            let outerTop = -outerScrollView.adjustedContentInset.top
            let outerBottom = max(
                outerTop,
                outerScrollView.contentSize.height
                    - outerScrollView.bounds.height
                    + outerScrollView.adjustedContentInset.bottom
            )
            let targetOuterY = min(
                max(outerScrollView.contentOffset.y + overflow, outerTop),
                outerBottom
            )

            if abs(targetOuterY - outerScrollView.contentOffset.y) > 0.5 {
                outerScrollView.setContentOffset(
                    CGPoint(x: outerScrollView.contentOffset.x, y: targetOuterY),
                    animated: false
                )
            }

            innerScrollView.isForwardingOffset = false
        }

        private static func findAncestorScrollView(
            from view: UIView?,
            excluding excludedScrollView: UIScrollView
        ) -> UIScrollView? {
            var current = view
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView, scrollView !== excludedScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }
    }
}

private final class ChainedUIScrollView: UIScrollView {
    weak var outerScrollView: UIScrollView?
    var isForwardingOffset = false
}
#endif
