import Foundation

struct SharedFolderCatalog: Codable {
    let schemaVersion: Int
    let userId: String
    let defaultFolderId: String
    let exportedAt: String
    let folders: [SharedFolder]
}

struct SharedFolder: Codable {
    let id: String
    let name: String
    let parentId: String?
    let color: String
    let isDefault: Bool
    let displayPath: String
    let level: Int
}

struct PendingShare: Codable {
    let id: String
    let userId: String
    let url: String
    let sharedText: String?
    let folderId: String
    let folderDisplayPath: String
    let enqueuedAt: String
    let source: String
    let tags: [String]?
    let newFolderName: String?
    let newFolderParentId: String?
    let newFolderParentPath: String?
}

enum AppGroupShareStore {
    static let appGroupIdentifier = "group.eu.savein.app.share"

    private static let catalogFilename = "folder_catalog.json"
    private static let pendingDirectoryName = "PendingShares"

    private static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    private static var catalogURL: URL? {
        containerURL?.appendingPathComponent(catalogFilename)
    }

    private static var pendingDirectoryURL: URL? {
        containerURL?.appendingPathComponent(
            pendingDirectoryName,
            isDirectory: true
        )
    }

    static func loadCatalog() throws -> SharedFolderCatalog? {
        guard let catalogURL else {
            throw StoreError.containerUnavailable
        }
        guard FileManager.default.fileExists(atPath: catalogURL.path) else {
            return nil
        }

        return try JSONDecoder().decode(
            SharedFolderCatalog.self,
            from: Data(contentsOf: catalogURL)
        )
    }

    static func writeCatalog(jsonObject: Any) throws {
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw StoreError.invalidJSON
        }
        guard let catalogURL else {
            throw StoreError.containerUnavailable
        }

        let data = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.sortedKeys]
        )
        try data.write(to: catalogURL, options: [.atomic])
    }

    static func clearCatalog() throws {
        guard let catalogURL else {
            throw StoreError.containerUnavailable
        }
        guard FileManager.default.fileExists(atPath: catalogURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: catalogURL)
    }

    static func enqueue(_ item: PendingShare) throws {
        guard let pendingDirectoryURL else {
            throw StoreError.containerUnavailable
        }

        try FileManager.default.createDirectory(
            at: pendingDirectoryURL,
            withIntermediateDirectories: true
        )

        let destination = pendingDirectoryURL
            .appendingPathComponent(item.id)
            .appendingPathExtension("json")
        let data = try JSONEncoder().encode(item)
        try data.write(to: destination, options: [.atomic])
    }

    static func readPendingJSONObjects() throws -> [[String: Any]] {
        guard let pendingDirectoryURL else {
            throw StoreError.containerUnavailable
        }
        guard FileManager.default.fileExists(atPath: pendingDirectoryURL.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: pendingDirectoryURL,
            includingPropertiesForKeys: nil
        )
        return try urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let object = try JSONSerialization.jsonObject(
                    with: Data(contentsOf: url)
                )
                guard let dictionary = object as? [String: Any] else {
                    throw StoreError.invalidJSON
                }
                return dictionary
            }
    }

    static func acknowledge(ids: [String]) throws {
        guard let pendingDirectoryURL else {
            throw StoreError.containerUnavailable
        }

        for id in ids where isSafeIdentifier(id) {
            let url = pendingDirectoryURL
                .appendingPathComponent(id)
                .appendingPathExtension("json")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil
    }

    enum StoreError: LocalizedError {
        case containerUnavailable
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .containerUnavailable:
                return "App Group container non disponibile."
            case .invalidJSON:
                return "Dati condivisi non validi."
            }
        }
    }
}
