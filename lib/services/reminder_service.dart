import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';

class ReminderService {
  ReminderService._internal();
  static final ReminderService instance = ReminderService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'savein_reminders';
  static const String _channelName = 'Reminder SaveIn';
  static const String _channelDesc =
      'Notifiche per i reminder di post e cartelle in SaveIn!';

  /// Callback impostato da main.dart per gestire il tap su notifica post.
  static Function(String postUrl, String postTitle)? onNotificationTapped;

  /// Callback impostato da main.dart per gestire il tap su notifica cartella.
  static Function(String folderId, String folderName)? onFolderNotificationTapped;

  // -----------------------------------------------------------------------
  // Inizializzazione
  // -----------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      // Fallback UTC
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    _initialized = true;
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(
      NotificationResponse response) {
    _handlePayload(response.payload);
  }

  void _onNotificationResponse(NotificationResponse response) {
    _handlePayload(response.payload);
  }

  static void _handlePayload(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final targetType = data['targetType'] as String? ?? 'post';
      final reminderId = data['reminderId'] as String? ?? '';

      if (targetType == 'folder') {
        final folderId = data['folderId'] as String? ?? '';
        final folderName = data['folderName'] as String? ?? '';
        if (folderId.isNotEmpty) {
          onFolderNotificationTapped?.call(folderId, folderName);
        }
      } else {
        final postUrl = data['postUrl'] as String? ?? '';
        final postTitle = data['postTitle'] as String? ?? '';
        if (postUrl.isNotEmpty) {
          onNotificationTapped?.call(postUrl, postTitle);
        }
      }

      if (reminderId.isNotEmpty) {
        _rescheduleYearlyAfterTap(reminderId);
      }
    } catch (_) {}
  }

  static Future<void> _rescheduleYearlyAfterTap(String reminderId) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('reminders')
          .doc(reminderId)
          .get();
      if (!doc.exists) return;
      final reminder = Reminder.fromFirestore(doc);
      if (reminder.isYearly && reminder.isActive) {
        await instance._scheduleNotification(reminder);
        await doc.reference
            .update({'lastTriggeredAt': FieldValue.serverTimestamp()});
      }
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // CRUD Firestore
  // -----------------------------------------------------------------------

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _remindersCollection =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('reminders');

  Future<Reminder> createReminder({
    required String postId,
    required String postTitle,
    required String postUrl,
    String? folderId,
    required int day,
    required int month,
    required int hour,
    required int minute,
    required bool isYearly,
  }) async {
    final notifId = _generateNotificationId();
    final now = DateTime.now();
    final data = {
      'postId': postId,
      'postTitle': postTitle,
      'postUrl': postUrl,
      'folderId': folderId,
      'reminderDay': day,
      'reminderMonth': month,
      'reminderHour': hour,
      'reminderMinute': minute,
      'isYearly': isYearly,
      'notificationId': notifId,
      'isActive': true,
      'createdAt': Timestamp.fromDate(now),
      'lastTriggeredAt': null,
    };

    final docRef = await _remindersCollection.add(data);
    final created = Reminder(
      id: docRef.id,
      postId: postId,
      postTitle: postTitle,
      postUrl: postUrl,
      folderId: folderId,
      reminderDay: day,
      reminderMonth: month,
      reminderHour: hour,
      reminderMinute: minute,
      isYearly: isYearly,
      notificationId: notifId,
      isActive: true,
      createdAt: now,
    );

    if (!kIsWeb) {
      await _scheduleNotification(created);
    }
    return created;
  }

  Future<Reminder> createFolderReminder({
    required String folderId,
    required String folderName,
    required int day,
    required int month,
    required int hour,
    required int minute,
    required bool isYearly,
  }) async {
    final notifId = _generateNotificationId();
    final now = DateTime.now();
    final data = {
      'targetType': 'folder',
      'postId': '',
      'postTitle': '',
      'postUrl': '',
      'folderId': folderId,
      'folderName': folderName,
      'reminderDay': day,
      'reminderMonth': month,
      'reminderHour': hour,
      'reminderMinute': minute,
      'isYearly': isYearly,
      'notificationId': notifId,
      'isActive': true,
      'createdAt': Timestamp.fromDate(now),
      'lastTriggeredAt': null,
    };

    final docRef = await _remindersCollection.add(data);
    final created = Reminder(
      id: docRef.id,
      targetType: 'folder',
      postId: '',
      postTitle: '',
      postUrl: '',
      folderId: folderId,
      folderName: folderName,
      reminderDay: day,
      reminderMonth: month,
      reminderHour: hour,
      reminderMinute: minute,
      isYearly: isYearly,
      notificationId: notifId,
      isActive: true,
      createdAt: now,
    );

    if (!kIsWeb) {
      await _scheduleNotification(created);
    }
    return created;
  }

  Future<void> deleteReminder(Reminder reminder) async {
    if (!kIsWeb) {
      await _notifications.cancel(id: reminder.notificationId);
    }
    await _remindersCollection.doc(reminder.id).delete();
  }

  Stream<List<Reminder>> getPostReminders(String postId) {
    if (_userId == null) return const Stream.empty();
    return _remindersCollection
        .where('postId', isEqualTo: postId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Reminder.fromFirestore(d)).toList());
  }

  Stream<List<Reminder>> getFolderReminders(String folderId) {
    if (_userId == null) return const Stream.empty();
    return _remindersCollection
        .where('folderId', isEqualTo: folderId)
        .where('targetType', isEqualTo: 'folder')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Reminder.fromFirestore(d)).toList());
  }

  Future<List<Reminder>> getAllActiveReminders() async {
    if (_userId == null) return [];
    final snap =
        await _remindersCollection.where('isActive', isEqualTo: true).get();
    return snap.docs.map((d) => Reminder.fromFirestore(d)).toList();
  }

  Future<List<Reminder>> getDueRemindersToday() async {
    if (_userId == null) return [];
    final now = DateTime.now();
    final snap = await _remindersCollection
        .where('reminderDay', isEqualTo: now.day)
        .where('reminderMonth', isEqualTo: now.month)
        .where('isActive', isEqualTo: true)
        .get();
    return snap.docs.map((d) => Reminder.fromFirestore(d)).toList();
  }

  Future<void> rescheduleAllReminders() async {
    if (kIsWeb || !_initialized) return;
    final reminders = await getAllActiveReminders();
    for (final r in reminders) {
      await _scheduleNotification(r);
    }
  }

  // -----------------------------------------------------------------------
  // Scheduling notifiche locali
  // -----------------------------------------------------------------------

  Future<void> _scheduleNotification(Reminder reminder) async {
    if (kIsWeb || !_initialized) return;

    final scheduledDate = _nextScheduledDate(reminder.reminderDay,
        reminder.reminderMonth, reminder.reminderHour, reminder.reminderMinute, reminder.isYearly);
    if (scheduledDate == null) return;

    final payload = jsonEncode({
      'reminderId': reminder.id,
      'targetType': reminder.targetType,
      'postId': reminder.postId,
      'postTitle': reminder.postTitle,
      'postUrl': reminder.postUrl,
      'folderId': reminder.folderId ?? '',
      'folderName': reminder.folderName ?? '',
    });

    final String body;
    if (reminder.isFolderReminder) {
      final name = reminder.folderName?.isNotEmpty == true ? reminder.folderName! : 'una cartella';
      body = 'Dai un\'occhiata alla cartella "$name"';
    } else if (reminder.postTitle.isNotEmpty) {
      body = 'Hai un contenuto da rivedere: "${reminder.postTitle}"';
    } else {
      body = 'Hai un contenuto salvato da rivedere!';
    }

    await _notifications.zonedSchedule(
      id: reminder.notificationId,
      title: '📌 Reminder SaveIn!',
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  tz.TZDateTime? _nextScheduledDate(
      int day, int month, int hour, int minute, bool isYearly) {
    final now = tz.TZDateTime.now(tz.local);
    var candidate =
        tz.TZDateTime(tz.local, now.year, month, day, hour, minute);

    if (candidate.isBefore(now)) {
      candidate =
          tz.TZDateTime(tz.local, now.year + 1, month, day, hour, minute);
    }

    // Controlla che il giorno sia valido per quel mese
    try {
      final test = DateTime(candidate.year, candidate.month, candidate.day);
      if (test.month != month) return null;
    } catch (_) {
      return null;
    }

    return candidate;
  }

  // -----------------------------------------------------------------------
  // Utilities
  // -----------------------------------------------------------------------

  int _generateNotificationId() =>
      Random().nextInt(2147483647 - 100000) + 100000;

  Future<void> requestPermissions() async {
    if (kIsWeb || !_initialized) return;
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }
}
