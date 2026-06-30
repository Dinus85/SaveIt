import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import 'reminder_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class AppNotificationService {
  AppNotificationService._();

  static final AppNotificationService instance = AppNotificationService._();
  static final StreamController<DashboardNotificationPayload>
      _dashboardNotificationOpenController =
      StreamController<DashboardNotificationPayload>.broadcast();
  static final List<DashboardNotificationPayload> _pendingOpenedPayloads =
      <DashboardNotificationPayload>[];

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  bool _messageOpenedHandlersReady = false;

  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  Stream<DashboardNotificationPayload> get dashboardNotificationOpenedStream =>
      _dashboardNotificationOpenController.stream;

  List<DashboardNotificationPayload> takePendingOpenedPayloads() {
    final pending = List<DashboardNotificationPayload>.from(
      _pendingOpenedPayloads,
    );
    _pendingOpenedPayloads.clear();
    return pending;
  }

  Future<void> initializeForUser(String userId) async {
    _registerMessageOpenedHandlers();
    await _requestPermissionIfNeeded();
    await _saveCurrentToken(userId);
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
      _saveToken(userId, token);
    });
  }

  void _registerMessageOpenedHandlers() {
    if (_messageOpenedHandlersReady) return;
    _messageOpenedHandlersReady = true;

    _messageOpenedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Push opened app: ${message.data}');
      _handleNotificationPayload(message.data);
    });

    unawaited(_messaging
        .getInitialMessage()
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () => null,
        )
        .then((message) {
      if (message != null) {
        debugPrint('Push launched app: ${message.data}');
        _handleNotificationPayload(message.data);
      }
    }).catchError((Object error) {
      debugPrint('Initial push message skipped: $error');
      return null;
    }));
  }

  void _handleNotificationPayload(Map<String, dynamic> data) {
    debugPrint('Handling notification payload: $data');
    final type = (data['type'] ?? '').toString();
    if (type != 'dashboard_notification') return;

    final title = (data['title'] ??
            data['notificationTitle'] ??
            data['campaignTitle'] ??
            '')
        .toString()
        .trim();
    final body =
        (data['body'] ?? data['notificationBody'] ?? data['campaignBody'] ?? '')
            .toString()
            .trim();
    final campaignId = (data['campaignId'] ?? '').toString().trim();
    if (title.isEmpty && body.isEmpty && campaignId.isEmpty) return;

    final payload = DashboardNotificationPayload(
      title: title,
      body: body,
      campaignId: campaignId,
    );
    if (!_dashboardNotificationOpenController.hasListener) {
      _pendingOpenedPayloads.add(payload);
    }
    _dashboardNotificationOpenController.add(payload);
  }

  Future<void> _requestPermissionIfNeeded() async {
    try {
      await _messaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Notification permission request skipped/failed: $e');
    }
  }

  Future<void> _saveCurrentToken(String userId) async {
    try {
      final token = await _messaging.getToken().timeout(
            const Duration(seconds: 8),
          );
      if (token == null || token.isEmpty) return;
      await _saveToken(userId, token);
    } catch (e) {
      debugPrint('FCM token unavailable: $e');
    }
  }

  Future<void> _saveToken(String userId, String token) async {
    final tokenId = token.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('fcmTokens')
        .doc(tokenId)
        .set({
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
      'userId': userId,
    }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> unreadNotificationsStream(
    String userId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  Future<DashboardNotificationPayload?> loadCampaignPayload(
    String campaignId,
  ) async {
    final id = campaignId.trim();
    if (id.isEmpty) return null;
    try {
      final snap = await _firestore
          .collection('notification_campaigns')
          .doc(id)
          .get()
          .timeout(const Duration(seconds: 6));
      final data = snap.data();
      if (data == null) return null;
      final title = (data['title'] ?? '').toString().trim();
      final body = (data['body'] ?? '').toString().trim();
      if (title.isEmpty && body.isEmpty) return null;
      return DashboardNotificationPayload(
        title: title,
        body: body,
        campaignId: id,
      );
    } catch (e) {
      debugPrint('Campaign notification payload unavailable: $e');
      return null;
    }
  }

  Future<void> markAsRead({
    required String userId,
    required String notificationId,
  }) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId)
        .set({
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> disposeForCurrentUser() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    await _messageOpenedSubscription?.cancel();
    _messageOpenedSubscription = null;
    _messageOpenedHandlersReady = false;
  }
}

class AppNotificationListener extends StatefulWidget {
  final String userId;
  final Widget child;

  const AppNotificationListener({
    super.key,
    required this.userId,
    required this.child,
  });

  @override
  State<AppNotificationListener> createState() =>
      _AppNotificationListenerState();
}

class _AppNotificationListenerState extends State<AppNotificationListener> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  StreamSubscription<DashboardNotificationPayload>? _pushOpenSubscription;
  final Set<String> _shownNotificationIds = <String>{};
  final Set<String> _shownCampaignIds = <String>{};
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant AppNotificationListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _subscription?.cancel();
      _shownNotificationIds.clear();
      _initialize();
    }
  }

  Future<void> _initialize() async {
    _pushOpenSubscription?.cancel();
    _pushOpenSubscription = AppNotificationService
        .instance.dashboardNotificationOpenedStream
        .listen(_handlePushOpenedPayload, onError: (Object error) {
      debugPrint('Push notification open stream failed: $error');
    });
    _subscription = AppNotificationService.instance
        .unreadNotificationsStream(widget.userId)
        .listen(_handleSnapshot, onError: (Object error) {
      debugPrint('In-app notification stream failed: $error');
    });
    unawaited(AppNotificationService.instance.initializeForUser(widget.userId));
    unawaited(_initializeReminderNotifications());
    final pending = AppNotificationService.instance.takePendingOpenedPayloads();
    for (final payload in pending) {
      unawaited(_handlePushOpenedPayload(payload));
    }
  }

  Future<void> _initializeReminderNotifications() async {
    try {
      await ReminderService.instance.requestPermissions().timeout(
            const Duration(seconds: 5),
          );
      await ReminderService.instance.rescheduleAllReminders().timeout(
            const Duration(seconds: 10),
          );
    } catch (e) {
      debugPrint('Reminder notification init skipped/failed: $e');
    }
  }

  void _handleSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!mounted || _dialogShowing) return;

    // 🔥 FIX: Non mostrare notifiche se siamo nella dashboard admin
    try {
      final uri = Uri.base;
      final path = uri.path.toLowerCase();
      final fragment = uri.fragment.toLowerCase();
      final isDashboard = path.contains('/admin') || fragment.contains('admin');
      if (isDashboard) {
        debugPrint('Notifica in-app ignorata: l\'utente è nella dashboard');
        return;
      }
    } catch (_) {}

    final docs = snapshot.docs.where((doc) {
      final data = doc.data();
      return data['readAt'] == null;
    }).toList();
    if (docs.isEmpty) return;

    // Mostriamo la più recente non letta
    final doc = docs.first;
    if (_shownNotificationIds.contains(doc.id)) return;
    _shownNotificationIds.add(doc.id);
    _showNotificationDialog(doc);
  }

  Future<void> _handlePushOpenedPayload(
    DashboardNotificationPayload payload,
  ) async {
    if (!mounted) return;
    if (payload.campaignId.isNotEmpty &&
        _shownCampaignIds.contains(payload.campaignId)) {
      return;
    }

    var effectivePayload = payload;
    if (effectivePayload.title.isEmpty && effectivePayload.body.isEmpty) {
      final loaded = await AppNotificationService.instance
          .loadCampaignPayload(effectivePayload.campaignId);
      if (loaded == null) return;
      effectivePayload = loaded;
    }
    if (!mounted) return;
    if (effectivePayload.campaignId.isNotEmpty) {
      _shownCampaignIds.add(effectivePayload.campaignId);
    }
    await _showNotificationPayloadDialog(effectivePayload);
  }

  Future<void> _showNotificationDialog(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? <String, dynamic>{};
    final title = (data['title'] as String?)?.trim();
    final body = (data['body'] as String?)?.trim();
    if (title?.isNotEmpty != true && body?.isNotEmpty != true) return;

    try {
      if (!mounted) return;

      await _showNotificationPayloadDialog(
        DashboardNotificationPayload(
          title: title ?? '',
          body: body ?? '',
          campaignId: (data['campaignId'] ?? '').toString(),
        ),
      );

      await AppNotificationService.instance.markAsRead(
        userId: widget.userId,
        notificationId: doc.id,
      );
    } catch (e) {
      debugPrint('In-app notification dialog failed: $e');
    }
  }

  Future<void> _showNotificationPayloadDialog(
    DashboardNotificationPayload payload,
  ) async {
    if (_dialogShowing || !mounted) return;
    _dialogShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  payload.title.isNotEmpty ? payload.title : 'Notifica',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            payload.body,
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Dashboard notification dialog failed: $e');
    } finally {
      _dialogShowing = false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pushOpenSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class DashboardNotificationPayload {
  final String title;
  final String body;
  final String campaignId;

  const DashboardNotificationPayload({
    required this.title,
    required this.body,
    required this.campaignId,
  });
}
