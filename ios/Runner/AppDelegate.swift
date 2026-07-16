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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
