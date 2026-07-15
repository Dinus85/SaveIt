// Extension-safe subset of receive_sharing_intent 1.8.1 (no Flutter APIs).
import UIKit
import Social
import MobileCoreServices
import Photos
import AVFoundation

let kSchemePrefix = "ShareMedia"
let kUserDefaultsKey = "ShareKey"
let kUserDefaultsMessageKey = "ShareMessageKey"
let kAppGroupIdKey = "AppGroupId"

class SharedMediaFile: Codable {
    var path: String
    var mimeType: String?
    var thumbnail: String?
    var duration: Double?
    var message: String?
    var type: SharedMediaType

    init(
        path: String,
        mimeType: String? = nil,
        thumbnail: String? = nil,
        duration: Double? = nil,
        message: String? = nil,
        type: SharedMediaType
    ) {
        self.path = path
        self.mimeType = mimeType
        self.thumbnail = thumbnail
        self.duration = duration
        self.message = message
        self.type = type
    }
}

enum SharedMediaType: String, Codable, CaseIterable {
    case image
    case video
    case text
    case file
    case url

    var toUTTypeIdentifier: String {
        if #available(iOS 14.0, *) {
            switch self {
            case .image: return UTType.image.identifier
            case .video: return UTType.movie.identifier
            case .text: return UTType.text.identifier
            case .file: return UTType.fileURL.identifier
            case .url: return UTType.url.identifier
            }
        }
        switch self {
        case .image: return "public.image"
        case .video: return "public.movie"
        case .text: return "public.text"
        case .file: return "public.file-url"
        case .url: return "public.url"
        }
    }
}

class RSIShareViewController: SLComposeServiceViewController {
    var hostAppBundleIdentifier = ""
    var appGroupId = ""
    var sharedMedia: [SharedMediaFile] = []

    open func shouldAutoRedirect() -> Bool {
        true
    }

    override func isContentValid() -> Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadIds()
    }

    override func didSelectPost() {
        saveAndRedirect(message: contentText)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let content = extensionContext!.inputItems[0] as? NSExtensionItem {
            if let contents = content.attachments {
                for (index, attachment) in contents.enumerated() {
                    for type in SharedMediaType.allCases {
                        if attachment.hasItemConformingToTypeIdentifier(type.toUTTypeIdentifier) {
                            attachment.loadItem(forTypeIdentifier: type.toUTTypeIdentifier) { [weak self] data, error in
                                guard let this = self, error == nil else {
                                    self?.dismissWithError()
                                    return
                                }
                                switch type {
                                case .text:
                                    if let text = data as? String {
                                        this.handleMedia(forLiteral: text, type: type, index: index, content: content)
                                    }
                                case .url:
                                    if let url = data as? URL {
                                        this.handleMedia(
                                            forLiteral: url.absoluteString,
                                            type: type,
                                            index: index,
                                            content: content
                                        )
                                    }
                                default:
                                    if let url = data as? URL {
                                        this.handleMedia(forFile: url, type: type, index: index, content: content)
                                    } else if let image = data as? UIImage {
                                        this.handleMedia(forUIImage: image, type: type, index: index, content: content)
                                    }
                                }
                            }
                            break
                        }
                    }
                }
            }
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private func loadIds() {
        let shareExtensionAppBundleIdentifier = Bundle.main.bundleIdentifier!
        let lastIndexOfPoint = shareExtensionAppBundleIdentifier.lastIndex(of: ".")!
        hostAppBundleIdentifier = String(shareExtensionAppBundleIdentifier[..<lastIndexOfPoint])
        let customAppGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        appGroupId = customAppGroupId ?? "group.\(hostAppBundleIdentifier)"
    }

    private func handleMedia(forLiteral item: String, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        sharedMedia.append(SharedMediaFile(
            path: item,
            mimeType: type == .text ? "text/plain" : nil,
            type: type
        ))
        if index == (content.attachments?.count ?? 0) - 1, shouldAutoRedirect() {
            saveAndRedirect()
        }
    }

    private func handleMedia(forUIImage image: UIImage, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        let tempPath = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!
            .appendingPathComponent("TempImage.png")
        if writeTempFile(image, to: tempPath) {
            let newPathDecoded = tempPath.absoluteString.removingPercentEncoding!
            sharedMedia.append(SharedMediaFile(
                path: newPathDecoded,
                mimeType: type == .image ? "image/png" : nil,
                type: type
            ))
        }
        if index == (content.attachments?.count ?? 0) - 1, shouldAutoRedirect() {
            saveAndRedirect()
        }
    }

    private func handleMedia(forFile url: URL, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        let fileName = getFileName(from: url, type: type)
        let newPath = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!
            .appendingPathComponent(fileName)

        if copyFile(at: url, to: newPath) {
            let newPathDecoded = newPath.absoluteString.removingPercentEncoding!
            if type == .video, let videoInfo = getVideoInfo(from: url) {
                sharedMedia.append(SharedMediaFile(
                    path: newPathDecoded,
                    mimeType: url.mimeType(),
                    thumbnail: videoInfo.thumbnail?.removingPercentEncoding,
                    duration: videoInfo.duration,
                    type: type
                ))
            } else {
                sharedMedia.append(SharedMediaFile(
                    path: newPathDecoded,
                    mimeType: url.mimeType(),
                    type: type
                ))
            }
        }

        if index == (content.attachments?.count ?? 0) - 1, shouldAutoRedirect() {
            saveAndRedirect()
        }
    }

    private func saveAndRedirect(message: String? = nil) {
        let userDefaults = UserDefaults(suiteName: appGroupId)
        userDefaults?.set(toData(data: sharedMedia), forKey: kUserDefaultsKey)
        userDefaults?.set(message, forKey: kUserDefaultsMessageKey)
        userDefaults?.synchronize()
        redirectToHostApp()
    }

    private func redirectToHostApp() {
        loadIds()
        guard let url = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else { return }
        var responder = self as UIResponder?

        if #available(iOS 18.0, *) {
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                }
                responder = responder?.next
            }
        } else {
            let selectorOpenURL = sel_registerName("openURL:")
            while responder != nil {
                if responder?.responds(to: selectorOpenURL) == true {
                    _ = responder?.perform(selectorOpenURL, with: url)
                }
                responder = responder?.next
            }
        }

        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func dismissWithError() {
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func getFileName(from url: URL, type: SharedMediaType) -> String {
        var name = url.lastPathComponent
        if name.isEmpty {
            switch type {
            case .image: name = UUID().uuidString + ".png"
            case .video: name = UUID().uuidString + ".mp4"
            case .text: name = UUID().uuidString + ".txt"
            default: name = UUID().uuidString
            }
        }
        return name
    }

    private func writeTempFile(_ image: UIImage, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try image.pngData()?.write(to: dstURL)
            return true
        } catch {
            return false
        }
    }

    private func copyFile(at srcURL: URL, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            return true
        } catch {
            return false
        }
    }

    private func getVideoInfo(from url: URL) -> (thumbnail: String?, duration: Double)? {
        let asset = AVAsset(url: url)
        let duration = (CMTimeGetSeconds(asset.duration) * 1000).rounded()
        let thumbnailPath = getThumbnailPath(for: url)

        if FileManager.default.fileExists(atPath: thumbnailPath.path) {
            return (thumbnail: thumbnailPath.absoluteString, duration: duration)
        }

        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        assetImgGenerate.maximumSize = CGSize(width: 360, height: 360)
        do {
            let img = try assetImgGenerate.copyCGImage(
                at: CMTimeMakeWithSeconds(600, preferredTimescale: 1),
                actualTime: nil
            )
            try UIImage(cgImage: img).pngData()?.write(to: thumbnailPath)
            return (thumbnail: thumbnailPath.absoluteString, duration: duration)
        } catch {
            return nil
        }
    }

    private func getThumbnailPath(for url: URL) -> URL {
        let fileName = Data(url.lastPathComponent.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "==", with: "")
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!
            .appendingPathComponent("\(fileName).jpg")
    }

    private func toData(data: [SharedMediaFile]) -> Data {
        try! JSONEncoder().encode(data)
    }
}

private extension URL {
    func mimeType() -> String {
        if #available(iOS 14.0, *) {
            if let mimeType = UTType(filenameExtension: pathExtension)?.preferredMIMEType {
                return mimeType
            }
        } else if let uti = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            pathExtension as NSString,
            nil
        )?.takeRetainedValue(),
            let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
            return mimetype as String
        }
        return "application/octet-stream"
    }
}
