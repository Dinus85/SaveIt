package com.example.saveit

import android.content.Context
import android.view.LayoutInflater
import android.widget.Button
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.NativeAdFactory

class PinterestPinNativeAdFactory(private val context: Context) : NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.native_ad_pinterest_pin, null) as NativeAdView

        val mediaView = adView.findViewById<MediaView>(R.id.ad_media)
        adView.mediaView = mediaView

        val headline = adView.findViewById<TextView>(R.id.ad_headline)
        headline.text = nativeAd.headline
        adView.headlineView = headline

        val body = adView.findViewById<TextView>(R.id.ad_body)
        body.text = nativeAd.body
        body.visibility = if (nativeAd.body.isNullOrBlank()) android.view.View.GONE else android.view.View.VISIBLE
        adView.bodyView = body

        val advertiser = adView.findViewById<TextView>(R.id.ad_advertiser)
        advertiser.text = nativeAd.advertiser?.takeIf { it.isNotBlank() } ?: "Sponsorizzato"
        adView.advertiserView = advertiser

        val cta = adView.findViewById<Button>(R.id.ad_call_to_action)
        cta.text = nativeAd.callToAction ?: "Apri"
        cta.visibility =
            if (nativeAd.callToAction.isNullOrBlank()) android.view.View.GONE else android.view.View.VISIBLE
        adView.callToActionView = cta

        adView.setNativeAd(nativeAd)
        return adView
    }
}
