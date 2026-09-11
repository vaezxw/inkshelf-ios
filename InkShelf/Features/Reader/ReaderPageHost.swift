import SwiftUI
import UIKit

/// UIKit reading host: paging scroll + center tap to toggle chrome.
struct ReaderPageHost: UIViewControllerRepresentable {
    var pages: [String]
    @Binding var pageIndex: Int
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var textColor: UIColor
    var backgroundColor: UIColor
    var onToggleChrome: () -> Void
    var onTurnPastEnd: () -> Void
    var onTurnPastStart: () -> Void

    func makeUIViewController(context: Context) -> ReaderPagingController {
        let controller = ReaderPagingController()
        controller.onToggleChrome = onToggleChrome
        controller.onTurnPastEnd = onTurnPastEnd
        controller.onTurnPastStart = onTurnPastStart
        controller.apply(
            pages: pages,
            pageIndex: pageIndex,
            fontSize: fontSize,
            lineHeight: lineHeight,
            textColor: textColor,
            backgroundColor: backgroundColor
        )
        return controller
    }

    func updateUIViewController(_ controller: ReaderPagingController, context: Context) {
        controller.onToggleChrome = onToggleChrome
        controller.onTurnPastEnd = onTurnPastEnd
        controller.onTurnPastStart = onTurnPastStart
        controller.apply(
            pages: pages,
            pageIndex: pageIndex,
            fontSize: fontSize,
            lineHeight: lineHeight,
            textColor: textColor,
            backgroundColor: backgroundColor
        )
        controller.syncPageIndexFromSwiftUI(pageIndex)
    }
}

final class ReaderPagingController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var onToggleChrome: (() -> Void)?
    var onTurnPastEnd: (() -> Void)?
    var onTurnPastStart: (() -> Void)?

    private var pageVC: UIPageViewController?
    private var pages: [String] = [""]
    private var currentIndex = 0
    private var fontSize: CGFloat = 18
    private var lineHeight: CGFloat = 1.7
    private var textColor: UIColor = .label
    private var backgroundColor: UIColor = .systemBackground
    private var isApplying = false
    private var pendingPageIndex: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundColor

        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 8]
        )
        pager.dataSource = self
        pager.delegate = self
        addChild(pager)
        pager.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pager.view)
        NSLayoutConstraint.activate([
            pager.view.topAnchor.constraint(equalTo: view.topAnchor),
            pager.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pager.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        pager.didMove(toParent: self)
        pageVC = pager

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        reloadCurrentPage(animated: false)
        if let pending = pendingPageIndex {
            pendingPageIndex = nil
            syncPageIndexFromSwiftUI(pending)
        }
    }

    func apply(
        pages: [String],
        pageIndex: Int,
        fontSize: CGFloat,
        lineHeight: CGFloat,
        textColor: UIColor,
        backgroundColor: UIColor
    ) {
        let normalized = pages.isEmpty ? [""] : pages
        let styleChanged =
            self.fontSize != fontSize
            || self.lineHeight != lineHeight
            || self.textColor != textColor
            || self.backgroundColor != backgroundColor
        let contentChanged = self.pages != normalized

        self.pages = normalized
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        if isViewLoaded {
            view.backgroundColor = backgroundColor
        }

        let idx = min(max(pageIndex, 0), normalized.count - 1)
        currentIndex = idx
        guard let pageVC else { return }
        if contentChanged || styleChanged || pageVC.viewControllers?.isEmpty != false {
            reloadCurrentPage(animated: false)
        }
    }

    func syncPageIndexFromSwiftUI(_ index: Int) {
        guard !isApplying else { return }
        guard let pageVC else {
            pendingPageIndex = index
            return
        }
        let idx = min(max(index, 0), max(pages.count - 1, 0))
        guard idx != currentIndex else { return }
        let direction: UIPageViewController.NavigationDirection = idx > currentIndex ? .forward : .reverse
        currentIndex = idx
        let page = makePage(at: idx)
        isApplying = true
        pageVC.setViewControllers([page], direction: direction, animated: true) { [weak self] _ in
            self?.isApplying = false
        }
    }

    private func reloadCurrentPage(animated: Bool) {
        guard let pageVC else { return }
        let idx = min(max(currentIndex, 0), max(pages.count - 1, 0))
        currentIndex = idx
        isApplying = true
        pageVC.setViewControllers([makePage(at: idx)], direction: .forward, animated: animated) { [weak self] _ in
            self?.isApplying = false
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        let width = view.bounds.width
        if point.x < width * 0.22 {
            turnBackward()
        } else if point.x > width * 0.78 {
            turnForward()
        } else {
            onToggleChrome?()
        }
    }

    private func turnForward() {
        guard let pageVC else { return }
        if currentIndex < pages.count - 1 {
            let next = currentIndex + 1
            currentIndex = next
            isApplying = true
            pageVC.setViewControllers([makePage(at: next)], direction: .forward, animated: true) { [weak self] _ in
                self?.isApplying = false
                NotificationCenter.default.post(name: .readerPageDidChange, object: next)
            }
        } else {
            onTurnPastEnd?()
        }
    }

    private func turnBackward() {
        guard let pageVC else { return }
        if currentIndex > 0 {
            let prev = currentIndex - 1
            currentIndex = prev
            isApplying = true
            pageVC.setViewControllers([makePage(at: prev)], direction: .reverse, animated: true) { [weak self] _ in
                self?.isApplying = false
                NotificationCenter.default.post(name: .readerPageDidChange, object: prev)
            }
        } else {
            onTurnPastStart?()
        }
    }

    private func makePage(at index: Int) -> ReaderTextPageController {
        let page = ReaderTextPageController()
        page.configure(
            text: pages[index],
            fontSize: fontSize,
            lineHeight: lineHeight,
            textColor: textColor,
            backgroundColor: backgroundColor,
            index: index
        )
        return page
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? ReaderTextPageController else { return nil }
        let idx = page.pageIndex
        guard idx > 0 else { return nil }
        return makePage(at: idx - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? ReaderTextPageController else { return nil }
        let idx = page.pageIndex
        guard idx + 1 < pages.count else { return nil }
        return makePage(at: idx + 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let page = pageViewController.viewControllers?.first as? ReaderTextPageController else { return }
        currentIndex = page.pageIndex
        NotificationCenter.default.post(name: .readerPageDidChange, object: currentIndex)
    }
}

final class ReaderTextPageController: UIViewController {
    private let textView = UITextView()
    private(set) var pageIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func configure(
        text: String,
        fontSize: CGFloat,
        lineHeight: CGFloat,
        textColor: UIColor,
        backgroundColor: UIColor,
        index: Int
    ) {
        pageIndex = index
        view.backgroundColor = backgroundColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeight
        textView.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph,
            ]
        )
    }
}

extension Notification.Name {
    static let readerPageDidChange = Notification.Name("inkshelf.readerPageDidChange")
}

/// Vertical continuous reading mode.
struct ReaderScrollHost: UIViewRepresentable {
    var text: String
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var textColor: UIColor
    var backgroundColor: UIColor
    var onToggleChrome: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.backgroundColor = backgroundColor
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        tv.textContainer.lineFragmentPadding = 0
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tv.addGestureRecognizer(tap)
        context.coordinator.onToggleChrome = onToggleChrome
        apply(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onToggleChrome = onToggleChrome
        apply(tv)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func apply(_ tv: UITextView) {
        tv.backgroundColor = backgroundColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeight
        tv.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph,
            ]
        )
    }

    final class Coordinator: NSObject {
        var onToggleChrome: (() -> Void)?
        @objc func tapped() { onToggleChrome?() }
    }
}
