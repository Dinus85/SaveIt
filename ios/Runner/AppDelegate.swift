import Flutter
import UIKit
import GoogleMobileAds
import google_mobile_ads

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
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "pinterestPin",
      nativeAdFactory: PinterestPinNativeAdFactory()
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

class PinterestPinNativeAdFactory: NSObject, FLTNativeAdFactory {
  func createNativeAd(
    _ nativeAd: NativeAd,
    customOptions: [AnyHashable: Any]? = nil
  ) -> NativeAdView? {
    let adView = NativeAdView()
    adView.backgroundColor = .white
    adView.layer.cornerRadius = 12
    adView.clipsToBounds = true
    adView.translatesAutoresizingMaskIntoConstraints = false

    let mediaView = MediaView()
    mediaView.translatesAutoresizingMaskIntoConstraints = false
    adView.mediaView = mediaView
    adView.addSubview(mediaView)

    let badge = UILabel()
    badge.text = nativeAd.advertiser?.isEmpty == false ? nativeAd.advertiser : "Sponsorizzato"
    badge.font = .boldSystemFont(ofSize: 10)
    badge.textColor = .white
    badge.backgroundColor = UIColor(white: 0.07, alpha: 0.8)
    badge.textAlignment = .center
    badge.translatesAutoresizingMaskIntoConstraints = false
    adView.advertiserView = badge
    adView.addSubview(badge)

    let headline = UILabel()
    headline.text = nativeAd.headline
    headline.font = .boldSystemFont(ofSize: 14)
    headline.textColor = UIColor(white: 0.12, alpha: 1)
    headline.numberOfLines = 2
    headline.translatesAutoresizingMaskIntoConstraints = false
    adView.headlineView = headline
    adView.addSubview(headline)

    let body = UILabel()
    body.text = nativeAd.body
    body.font = .systemFont(ofSize: 12)
    body.textColor = UIColor(white: 0.38, alpha: 1)
    body.numberOfLines = 2
    body.translatesAutoresizingMaskIntoConstraints = false
    adView.bodyView = body
    adView.addSubview(body)

    let cta = UIButton(type: .system)
    cta.setTitle(nativeAd.callToAction ?? "Apri", for: .normal)
    cta.setTitleColor(.white, for: .normal)
    cta.backgroundColor = UIColor(white: 0.17, alpha: 1)
    cta.titleLabel?.font = .boldSystemFont(ofSize: 13)
    cta.layer.cornerRadius = 8
    cta.translatesAutoresizingMaskIntoConstraints = false
    adView.callToActionView = cta
    adView.addSubview(cta)

    NSLayoutConstraint.activate([
      mediaView.topAnchor.constraint(equalTo: adView.topAnchor),
      mediaView.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
      mediaView.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
      mediaView.heightAnchor.constraint(equalToConstant: 180),
      badge.topAnchor.constraint(equalTo: adView.topAnchor, constant: 8),
      badge.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 8),
      headline.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: 8),
      headline.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 10),
      headline.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -10),
      body.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 4),
      body.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
      body.trailingAnchor.constraint(equalTo: headline.trailingAnchor),
      cta.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 8),
      cta.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
      cta.trailingAnchor.constraint(equalTo: headline.trailingAnchor),
      cta.heightAnchor.constraint(equalToConstant: 36),
      cta.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -10),
    ])

    adView.nativeAd = nativeAd
    return adView
  }
}
