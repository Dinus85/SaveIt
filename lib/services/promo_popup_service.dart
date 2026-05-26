import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';

const _kCrossDismissedAt = 'promo_cross_dismissed_at';
const _kCrossActivated = 'promo_cross_activated';
const _kGenericDismissedAt = 'promo_generic_dismissed_at';
const _k48h = Duration(hours: 48);

class PromoPopupService {
  PromoPopupService._();

  // ── Lettura preferenze ────────────────────────────────────────────────────

  static Future<bool> _isCrossPromoActivated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kCrossActivated) ?? false;
  }

  static Future<bool> _isDismissedRecently(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(key);
    if (ts == null) return false;
    return DateTime.now().millisecondsSinceEpoch - ts < _k48h.inMilliseconds;
  }

  // ── Scrittura preferenze ──────────────────────────────────────────────────

  static Future<void> markCrossPromoDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _kCrossDismissedAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> markCrossPromoActivated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCrossActivated, true);
  }

  static Future<void> markGenericPromoDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _kGenericDismissedAt, DateTime.now().millisecondsSinceEpoch);
  }

  // ── Logica di visibilità ──────────────────────────────────────────────────

  static Future<PromotionBanner?> getBannerToShow() async {
    final banner = await AuthService().getActivePromotionBanner();
    if (banner == null) return null;

    final activated = await _isCrossPromoActivated();

    if (banner.isCrossPromo) {
      if (activated)
        return null; // cross promo già attivata, non mostrare mai più
      final dismissed = await _isDismissedRecently(_kCrossDismissedAt);
      if (dismissed) return null;
      return banner;
    } else {
      // generic promo
      final dismissed = await _isDismissedRecently(_kGenericDismissedAt);
      if (dismissed) return null;
      return banner;
    }
  }

  // ── Popup ─────────────────────────────────────────────────────────────────

  static Future<void> showIfNeeded(
    BuildContext context, {
    required Future<void> Function(BuildContext context) onActivateCrossPromo,
    required Future<void> Function() onOpenOtherApp,
  }) async {
    final banner = await getBannerToShow();
    if (banner == null) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PromoDialog(
        banner: banner,
        onActivateCrossPromo: onActivateCrossPromo,
        onOpenOtherApp: onOpenOtherApp,
      ),
    );
  }
}

// ── Widget popup ──────────────────────────────────────────────────────────────

class _PromoDialog extends StatelessWidget {
  final PromotionBanner banner;
  final Future<void> Function(BuildContext context) onActivateCrossPromo;
  final Future<void> Function() onOpenOtherApp;

  const _PromoDialog({
    required this.banner,
    required this.onActivateCrossPromo,
    required this.onOpenOtherApp,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: banner.isCrossPromo ? null : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.hardEdge,
      child: banner.isCrossPromo
          ? _CrossPromoContent(
              banner: banner,
              onActivate: onActivateCrossPromo,
              onOpenOtherApp: onOpenOtherApp,
            )
          : _GenericPromoContent(banner: banner),
    );
  }
}

// ── Cross promo ───────────────────────────────────────────────────────────────

class _CrossPromoContent extends StatelessWidget {
  final PromotionBanner banner;
  final Future<void> Function(BuildContext context) onActivate;
  final Future<void> Function() onOpenOtherApp;

  const _CrossPromoContent({
    required this.banner,
    required this.onActivate,
    required this.onOpenOtherApp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header con close button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              const Icon(Icons.local_fire_department, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  banner.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () async {
                  await PromoPopupService.markCrossPromoDismissed();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),

        // Immagine (se presente)
        if (banner.imageUrl.trim().isNotEmpty)
          AspectRatio(
            aspectRatio: 2.5,
            child: Image.network(
              banner.imageUrl.trim(),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

        // Messaggio
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            banner.message,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ),

        // Bottoni
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  await AuthService().recordPromotionBannerEvent(
                    promotionId: banner.id,
                    eventType: 'click',
                    placement: 'savein_popup',
                  );
                  await PromoPopupService.markCrossPromoActivated();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    await onActivate(context);
                  }
                },
                icon: const Icon(Icons.card_giftcard),
                label: Text(banner.ctaLabel.isNotEmpty
                    ? banner.ctaLabel
                    : 'Attiva promo'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await onOpenOtherApp();
                },
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  banner.secondaryCtaLabel.trim().isNotEmpty
                      ? banner.secondaryCtaLabel
                      : 'Apri SmartChef',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Generic promo ─────────────────────────────────────────────────────────────

class _GenericPromoContent extends StatelessWidget {
  final PromotionBanner banner;

  const _GenericPromoContent({required this.banner});

  @override
  Widget build(BuildContext context) {
    if (banner.imageUrl.trim().isEmpty) {
      // Nessuna immagine: chiudi subito
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await PromoPopupService.markGenericPromoDismissed();
        if (context.mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // Immagine tappabile
        GestureDetector(
          onTap: () async {
            await AuthService().recordPromotionBannerEvent(
              promotionId: banner.id,
              eventType: 'click',
              placement: 'savein_popup',
            );
            if (banner.actionUrl.trim().isNotEmpty) {
              await launchUrl(
                Uri.parse(banner.actionUrl),
                mode: LaunchMode.externalApplication,
              );
            }
          },
          child: AspectRatio(
            aspectRatio: 2.5,
            child: Image.network(
              banner.imageUrl.trim(),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
        // X di chiusura sovrapposta
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: () async {
              await PromoPopupService.markGenericPromoDismissed();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}
