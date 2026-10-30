import AppKit

@MainActor
enum DevelopmentCapture {
    static func schedule() {
        #if DEBUG
        guard let destination = ProcessInfo.processInfo.environment["SKILLATLAS_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }), let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: destination)) }
        }
        #endif
    }
}
