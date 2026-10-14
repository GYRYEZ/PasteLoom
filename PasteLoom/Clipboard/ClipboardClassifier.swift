import Foundation

struct ClipboardSnapshot: Sendable {
    let fileURLs: [URL]
    let imageData: Data?
    let urlString: String?
    let plainText: String?
    let rtfData: Data?

    init(fileURLs: [URL], imageData: Data?, urlString: String?, plainText: String?, rtfData: Data? = nil) {
        self.fileURLs = fileURLs
        self.imageData = imageData
        self.urlString = urlString
        self.plainText = plainText
        self.rtfData = rtfData
    }
}

enum ClipboardInput: Sendable {
    case text(String)
    case url(String)
    case image(Data)
    case files([FileReference])
    case richText(plain: String, rtfData: Data)
    case video(FileReference)
}

enum ClipboardClassifier {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "flv", "wmv"]

    static func classify(_ snapshot: ClipboardSnapshot) -> ClipboardInput? {
        let files = snapshot.fileURLs.filter(\.isFileURL).map { url in
            FileReference(url: url,
                          name: url.lastPathComponent,
                          fileExtension: url.pathExtension,
                          typeIdentifier: (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier)
        }
        if files.count == 1, let first = files.first, videoExtensions.contains(first.fileExtension.lowercased()) {
            return .video(first)
        }
        if !files.isEmpty { return .files(files) }
        if let imageData = snapshot.imageData, !imageData.isEmpty { return .image(imageData) }
        if let url = validWebURL(snapshot.urlString) ?? validWebURL(snapshot.plainText) { return .url(url) }
        if let rtf = snapshot.rtfData, let text = snapshot.plainText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .richText(plain: text, rtfData: rtf)
        }
        if let text = snapshot.plainText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return nil
    }

    private static func validWebURL(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty,
              raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.contains(where: \.isWhitespace),
              let components = URLComponents(string: raw),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty else { return nil }
        return raw
    }
}

enum URLCleaner {
    private static let trackingNames: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "igshid"]

    static func clean(_ raw: String) -> String {
        guard var components = URLComponents(string: raw),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let items = components.queryItems else { return raw }
        let retained = items.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingNames.contains(name)
        }
        guard retained.count != items.count else { return raw }
        components.queryItems = retained.isEmpty ? nil : retained
        return components.string ?? raw
    }
}

struct CaptureTypeExclusions: Sendable {
    var text = false
    var url = false
    var image = false
    var file = false

    func excludes(_ input: ClipboardInput) -> Bool {
        switch input {
        case .text: text
        case .richText: text
        case .url: url
        case .image: image
        case .files, .video: file
        }
    }
}
