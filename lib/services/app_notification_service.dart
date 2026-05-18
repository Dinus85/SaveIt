import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class AppNotificationService {
  AppNotificationService._();

  static final AppNotificationService instance = AppNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  bool _messageOpenedHandlersReady = false;

  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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
      }
    }).catchError((Object error) {
      debugPrint('Initial push message skipped: $error');
      return null;
    }));
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
        .where('readAt', isNull: true)
        .limit(10)
        .snapshots();
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
  final Set<String> _shownNotificationIds = <String>{};
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
    _subscription = AppNotificationService.instance
        .unreadNotificationsStream(widget.userId)
        .listen(_handleSnapshot, onError: (Object error) {
      debugPrint('In-app notification stream failed: $error');
    });
    unawaited(AppNotificationService.instance.initializeForUser(widget.userId));
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

    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final doc = change.doc;
      if (_shownNotificationIds.contains(doc.id)) continue;
      _shownNotificationIds.add(doc.id);
      _showNotificationDialog(doc);
      break;
    }
  }

  Future<void> _showNotificationDialog(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? <String, dynamic>{};
    final title = (data['title'] as String?)?.trim();
    final body = (data['body'] as String?)?.trim();
    if (title?.isNotEmpty != true && body?.isNotEmpty != true) return;

    _dialogShowing = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title?.isNotEmpty == true ? title! : 'Notifica'),
          content: Text(body?.isNotEmpty == true ? body! : ''),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await AppNotificationService.instance.markAsRead(
        userId: widget.userId,
        notificationId: doc.id,
      );
    } catch (e) {
      debugPrint('In-app notification dialog failed: $e');
    } finally {
      _dialogShowing = false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
