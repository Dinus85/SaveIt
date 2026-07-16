import Flutter
import Foundation

final class ShareExtensionBridge: NSObject, FlutterPlugin {
    private static let channelName = "eu.savein.app/share_extension"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(ShareExtensionBridge(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            switch call.method {
            case "exportCatalog":
                guard let catalog = call.arguments as? [String: Any] else {
                    result(
                        FlutterError(
                            code: "invalid_catalog",
                            message: "Catalogo cartelle non valido.",
                            details: nil
                        )
                    )
                    return
                }
                try AppGroupShareStore.writeCatalog(jsonObject: catalog)
                result(nil)

            case "clearCatalog":
                try AppGroupShareStore.clearCatalog()
                result(nil)

            case "readPendingShares":
                result(try AppGroupShareStore.readPendingJSONObjects())

            case "acknowledgePendingShares":
                guard
                    let arguments = call.arguments as? [String: Any],
                    let ids = arguments["ids"] as? [String]
                else {
                    result(
                        FlutterError(
                            code: "invalid_ids",
                            message: "Identificativi coda non validi.",
                            details: nil
                        )
                    )
                    return
                }
                try AppGroupShareStore.acknowledge(ids: ids)
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        } catch {
            result(
                FlutterError(
                    code: "share_store_error",
                    message: error.localizedDescription,
                    details: nil
                )
            )
        }
    }
}
