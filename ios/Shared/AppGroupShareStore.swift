import Foundation

struct SharedFolderCatalog: Codable {
    let schemaVersion: Int
    let userId: String
    let defaultFolderId: String
    let exportedAt: String
    let folders: [SharedFolder]
    let limits: SharedPlanLimits?
}

struct SharedPlanLimits: Codable {
    let rootFoldersEnabled: Bool
    let rootFolderLimit: Int
    let childFoldersEnabled: Bool
    let childFolderLimit: Int
    let folderLevelsEnabled: Bool
    let folderLevelLimit: Int
    let manualTagsEnabled: Bool
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

struct SharedAuthSession: Codable {
    let schemaVersion: Int
    let userId: String
    let idToken: String
    let expiresAt: String
    let exportedAt: String
    let saveEndpoint: String

    var isUsable: Bool {
        guard !idToken.isEmpty, let expiration = Self.parseISO8601(expiresAt) else {
            return false
        }
        return expiration.timeIntervalSinceNow > 60
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

struct SharedFolderDraft: Codable {
    let id: String
    let name: String
    let parentFolderId: String?
    let parentDraftId: String?
    let parentDisplayPath: String?
    let displayPath: String
    let level: Int
    let color: String
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
    let folderDrafts: [SharedFolderDraft]?
    let destinationDraftId: String?
}

struct LastShareResult: Codable {
    let schemaVersion: Int
    let postId: String
    let folderId: String?
    let destinationPath: String
    let url: String
    let savedAt: String
    let createdFolderCount: Int
}

enum AppGroupShareStore {
    static let appGroupIdentifier = "group.eu.savein.app.share"

    private static let catalogFilename = "folder_catalog.json"
    private static let authSessionFilename = "auth_session.json"
    private static let lastShareResultFilename = "last_share_result.json"
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

    private static var authSessionURL: URL? {
        containerURL?.appendingPathComponent(authSessionFilename)
    }

    private static var lastShareResultURL: URL? {
        containerURL?.appendingPathComponent(lastShareResultFilename)
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

    static func loadAuthSession() throws -> SharedAuthSession? {
        guard let authSessionURL else {
            throw StoreError.containerUnavailable
        }
        guard FileManager.default.fileExists(atPath: authSessionURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(
            SharedAuthSession.self,
            from: Data(contentsOf: authSessionURL)
        )
    }

    static func writeAuthSession(jsonObject: Any) throws {
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw StoreError.invalidJSON
        }
        guard let authSessionURL else {
            throw StoreError.containerUnavailable
        }
        let data = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.sortedKeys]
        )
        try data.write(to: authSessionURL, options: [.atomic])
    }

    static func clearAuthSession() throws {
        guard let authSessionURL else {
            throw StoreError.containerUnavailable
        }
        guard FileManager.default.fileExists(atPath: authSessionURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: authSessionURL)
    }

    static func writeLastShareResult(jsonObject: Any) throws {
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw StoreError.invalidJSON
        }
        guard let lastShareResultURL else {
            throw StoreError.containerUnavailable
        }
        let data = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.sortedKeys]
        )
        try data.write(to: lastShareResultURL, options: [.atomic])
    }

    static func consumeLastShareResultJSONObject() throws -> [String: Any]? {
        guard let lastShareResultURL else {
            throw StoreError.containerUnavailable
        }
        guard FileManager.default.fileExists(atPath: lastShareResultURL.path) else {
            return nil
        }
        let object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: lastShareResultURL)
        )
        guard let dictionary = object as? [String: Any] else {
            throw StoreError.invalidJSON
        }
        try FileManager.default.removeItem(at: lastShareResultURL)
        return dictionary
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
