import AppKit
import SwiftUI

struct WindowAspectRatio: NSViewRepresentable {
    let ratio: CGSize

    func makeNSView(context: Context) -> NSView {
        ConfiguringView(ratio: ratio)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        private let ratio: CGSize

        init(ratio: CGSize) {
            self.ratio = ratio
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.contentAspectRatio = ratio
            window?.contentMinSize = NSSize(width: 700, height: 438)
        }
    }
}