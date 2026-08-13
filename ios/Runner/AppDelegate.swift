import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let shareExtensionRegistrar = registrar(
      forPlugin: "ShareExtensionBridge"
    ) {
      ShareExtensionBridge.register(with: shareExtensionRegistrar)
    }
    if let adsRegistrar = registrar(forPlugin: "AdsEnvironment") {
      let adsChannel = FlutterMethodChannel(
        name: "eu.savein.app/ads",
        binaryMessenger: adsRegistrar.messenger()
      )
      adsChannel.setMethodCallHandler { call, result in
        if call.method == "isTestFlight" {
          let receiptName = Bundle.main.appStoreReceiptURL?.lastPathComponent
          result(receiptName == "sandboxReceipt")
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
