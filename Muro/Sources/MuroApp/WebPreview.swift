import SwiftUI
import WebKit
import MuroKit

struct WebPreview: NSViewRepresentable {
    let directory: URL

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        if let surface = WebSurface(directory: directory, frame: container.bounds) {
            context.coordinator.surface = surface
            container.addSubview(surface.view)
        }
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {}

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.surface?.invalidate()
        coordinator.surface = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var surface: WebSurface? }
}
