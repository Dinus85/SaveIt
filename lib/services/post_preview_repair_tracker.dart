// lib/services/post_preview_repair_tracker.dart
// Evita tentativi ripetuti di download anteprime per post senza immagine.

class PostPreviewRepairTracker {
  PostPreviewRepairTracker._();

  static final PostPreviewRepairTracker instance = PostPreviewRepairTracker._();

  bool _startupRepairStarted = false;
  final Set<String> _attemptedPostIds = <String>{};

  /// True se il batch di repair all'apertura e' gia' partito in questa sessione.
  bool get startupRepairStarted => _startupRepairStarted;

  bool tryBeginStartupRepair() {
    if (_startupRepairStarted) return false;
    _startupRepairStarted = true;
    return true;
  }

  bool wasAttempted(String postId) {
    if (postId.isEmpty) return false;
    return _attemptedPostIds.contains(postId);
  }

  void markAttempted(String postId) {
    if (postId.isEmpty) return;
    _attemptedPostIds.add(postId);
  }

  void resetForLogout() {
    _startupRepairStarted = false;
    _attemptedPostIds.clear();
  }
}
