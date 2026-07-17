// lib/services/post_preview_repair_tracker.dart
// Evita tentativi ripetuti di download anteprime per post senza immagine.

class PostPreviewRepairTracker {
  PostPreviewRepairTracker._();

  static final PostPreviewRepairTracker instance = PostPreviewRepairTracker._();

  bool _startupRepairStarted = false;
  DateTime? _lastRepairBatchAt;
  final Set<String> _attemptedPostIds = <String>{};

  /// True se il batch di repair all'apertura e' gia' partito in questa sessione.
  bool get startupRepairStarted => _startupRepairStarted;

  bool tryBeginStartupRepair() {
    if (_startupRepairStarted) return false;
    _startupRepairStarted = true;
    _lastRepairBatchAt = DateTime.now();
    return true;
  }

  /// Permette un nuovo batch (es. al resume) con cooldown anti-spam.
  bool tryBeginRepairBatch({
    Duration cooldown = const Duration(seconds: 20),
  }) {
    final last = _lastRepairBatchAt;
    if (last != null && DateTime.now().difference(last) < cooldown) {
      return false;
    }
    _startupRepairStarted = true;
    _lastRepairBatchAt = DateTime.now();
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

  void clearAttempt(String postId) {
    if (postId.isEmpty) return;
    _attemptedPostIds.remove(postId);
  }

  void resetForLogout() {
    _startupRepairStarted = false;
    _lastRepairBatchAt = null;
    _attemptedPostIds.clear();
  }
}
