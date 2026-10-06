import Foundation

/// Holds security-scoped grants while project media and build folders are in use.
final class FileAccess {
    private var held: [URL] = []
    private var paths = Set<String>()
    func remember(_ url: URL) -> Data? {
        hold(url)
        return try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    func restore(_ bookmarks: [String: Data]) {
        for data in bookmarks.values {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { hold(url) }
        }
    }
    private func hold(_ url: URL) {
        if paths.insert(url.path).inserted && url.startAccessingSecurityScopedResource() { held.append(url) }
    }
    deinit { for url in held { url.stopAccessingSecurityScopedResource() } }
}
