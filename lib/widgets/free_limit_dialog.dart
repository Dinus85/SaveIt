import 'package:flutter/material.dart';
import '../pages/account_page.dart';

class FreeLimitDialog extends StatelessWidget {
  final String feature;
  final String featureName;
  final String limitText;
  final bool isPremium;

  const FreeLimitDialog({
    super.key,
    required this.feature,
    required this.featureName,
    required this.limitText,
    this.isPremium = false,
  });

  static void show(
    BuildContext context, {
    required String feature,
    required String featureName,
    required String limitText,
    bool isPremium = false,
    String? title,
  }) {
    showDialog(
      context: context,
      builder: (context) => FreeLimitDialog(
        feature: feature,
        featureName: featureName,
        limitText: limitText,
        isPremium: isPremium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: EdgeInsets.zero,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isPremium
                      ? [Colors.orange.shade400, Colors.orange.shade700]
                      : [Colors.blue.shade400, Colors.blue.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Icon(
                    isPremium ? Icons.workspace_premium : Icons.lock_outline,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isPremium ? 'Limite raggiunto' : 'Passa a Premium',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    isPremium
                        ? 'Hai raggiunto il limite per questa funzione ($featureName).'
                        : 'Hai raggiunto il limite gratuito per questa funzione ($featureName).',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    limitText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!isPremium) ...[
                    const Text(
                      'Con Premium togli i limiti Free e usi SaveIn! senza pubblicità.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Chiudi',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (!isPremium)
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              AccountPage.showPremiumPurchaseDialog(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Passa a Premium',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
