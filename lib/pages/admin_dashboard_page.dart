import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';

class AdminDashboardPage extends StatefulWidget {
  final bool isDarkTheme;
  final ValueChanged<bool> onThemeChanged;

  const AdminDashboardPage({
    Key? key,
    required this.isDarkTheme,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _fixedCostsController =
      TextEditingController(text: '80');
  final TextEditingController _freeUserCostController =
      TextEditingController(text: '0,05');
  final TextEditingController _premiumUserCostController =
      TextEditingController(text: '0,20');
  final TextEditingController _premiumPriceController =
      TextEditingController(text: '4,99');
  final TextEditingController _freeAdRevenueController =
      TextEditingController(text: '0,10');
  final TextEditingController _paymentFeePercentController =
      TextEditingController(text: '15');
  final TextEditingController _dashboardAccessEmailController =
      TextEditingController();
  final TextEditingController _notificationTitleController =
      TextEditingController();
  final TextEditingController _notificationBodyController =
      TextEditingController();
  final TextEditingController _emailSubjectController =
      TextEditingController();
  final TextEditingController _emailBodyController =
      TextEditingController();

  String _searchQuery = '';
  AppUserRole? _roleFilter;
  bool? _marketingFilter; // ✅ NUOVO: Filtro marketing
  _AdminStatsPeriod _statsPeriod = _AdminStatsPeriod.all;
  _AdminDashboardSection _activeSection = _AdminDashboardSection.users;
  String? _selectedUserId;
  int _usersPage = 0;
  int _postsPage = 0;
  int _statsPostsPage = 0;
  int _foldersPage = 0;
  int _accessesPage = 0;
  String? _postSourceFilter;
  DashboardAccessRole _newDashboardAccessRole = DashboardAccessRole.author;
  bool _sendInAppNotification = false;
  bool _sendPushNotification = false;
  bool _sendingNotification = false;
  bool _sendEmailEnabled = false;
  bool _sendingEmail = false;
  int _emailTemplateIndex = 0;
  final Set<String> _expandedFolderIds = <String>{};
  final Set<String> _updatingUserIds = <String>{};
  final Set<String> _selectedUserIds = <String>{};
  static const int _pageSize = 20;
  static const int _previewTargetBytes = 100 * 1024;
  static const double _storageFreeBytes = 5 * 1024 * 1024 * 1024;
  static const double _storageDownloadFreeBytes = 100 * 1024 * 1024 * 1024;
  static const int _storageUploadOpsFree = 5000;
  static const int _firestoreWritesFreeDaily = 20000;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fixedCostsController.addListener(_onFinanceInputChanged);
    _freeUserCostController.addListener(_onFinanceInputChanged);
    _premiumUserCostController.addListener(_onFinanceInputChanged);
    _premiumPriceController.addListener(_onFinanceInputChanged);
    _freeAdRevenueController.addListener(_onFinanceInputChanged);
    _paymentFeePercentController.addListener(_onFinanceInputChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _fixedCostsController.removeListener(_onFinanceInputChanged);
    _freeUserCostController.removeListener(_onFinanceInputChanged);
    _premiumUserCostController.removeListener(_onFinanceInputChanged);
    _premiumPriceController.removeListener(_onFinanceInputChanged);
    _freeAdRevenueController.removeListener(_onFinanceInputChanged);
    _paymentFeePercentController.removeListener(_onFinanceInputChanged);
    _searchController.dispose();
    _fixedCostsController.dispose();
    _freeUserCostController.dispose();
    _premiumUserCostController.dispose();
    _premiumPriceController.dispose();
    _freeAdRevenueController.dispose();
    _paymentFeePercentController.dispose();
    _dashboardAccessEmailController.dispose();
    _notificationTitleController.dispose();
    _notificationBodyController.dispose();
    _emailSubjectController.dispose();
    _emailBodyController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _usersPage = 0;
    });
  }

  void _onFinanceInputChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<T> _pageItems<T>(List<T> items, int page) {
    final start = page * _pageSize;
    if (start >= items.length) return <T>[];
    final end = (start + _pageSize).clamp(0, items.length).toInt();
    return items.sublist(start, end);
  }

  int _maxPage(int totalItems) {
    if (totalItems <= 0) return 0;
    return ((totalItems - 1) / _pageSize).floor();
  }

  double _readMoney(TextEditingController controller) {
    final normalized = controller.text.trim().replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  String _formatMoney(double value) {
    final sign = value < 0 ? '-' : '';
    return '$sign€ ${value.abs().toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _formatPercent(double value) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')}%';
  }

  String _formatDataSize(double bytes) {
    const kb = 1024.0;
    const mb = 1024.0 * 1024.0;
    const gb = 1024.0 * 1024.0 * 1024.0;
    if (bytes >= gb)
      return '${(bytes / gb).toStringAsFixed(2).replaceAll('.', ',')} GB';
    if (bytes >= mb)
      return '${(bytes / mb).toStringAsFixed(1).replaceAll('.', ',')} MB';
    return '${(bytes / kb).toStringAsFixed(0).replaceAll('.', ',')} KB';
  }

  String _roleLabel(AppUserRole role) {
    switch (role) {
      case AppUserRole.free:
        return 'Free';
      case AppUserRole.premium:
        return 'Premium';
      case AppUserRole.admin:
        return 'Admin';
    }
  }

  Color _roleColor(AppUserRole role) {
    switch (role) {
      case AppUserRole.free:
        return Colors.grey.shade700;
      case AppUserRole.premium:
        return Colors.blue.shade700;
      case AppUserRole.admin:
        return Colors.deepPurple.shade700;
    }
  }

  String _dashboardRoleLabel(DashboardAccessRole role) {
    switch (role) {
      case DashboardAccessRole.none:
        return 'Nessuno';
      case DashboardAccessRole.author:
        return 'Autore';
      case DashboardAccessRole.editor:
        return 'Editore';
      case DashboardAccessRole.admin:
        return 'Admin';
    }
  }

  bool get _canManageDashboardAccess =>
      AuthService().currentUser?.canManageDashboardAccess ?? false;
  bool get _canManageUserRoles =>
      AuthService().currentUser?.canManageUserRoles ?? false;
  bool get _canBlockUsers => AuthService().currentUser?.canBlockUsers ?? false;
  bool get _canSendNotifications => _canBlockUsers;

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String _formatDateOnly(DateTime? date) {
    if (date == null) return '-';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }

  String _statsPeriodLabel(_AdminStatsPeriod period) {
    switch (period) {
      case _AdminStatsPeriod.last7Days:
        return 'Ultimi 7 giorni';
      case _AdminStatsPeriod.last30Days:
        return 'Ultimi 30 giorni';
      case _AdminStatsPeriod.last90Days:
        return 'Ultimi 90 giorni';
      case _AdminStatsPeriod.last365Days:
        return 'Ultimo anno';
      case _AdminStatsPeriod.all:
        return 'Tutto';
    }
  }

  DateTime? _statsPeriodStart(_AdminStatsPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case _AdminStatsPeriod.last7Days:
        return now.subtract(const Duration(days: 7));
      case _AdminStatsPeriod.last30Days:
        return now.subtract(const Duration(days: 30));
      case _AdminStatsPeriod.last90Days:
        return now.subtract(const Duration(days: 90));
      case _AdminStatsPeriod.last365Days:
        return now.subtract(const Duration(days: 365));
      case _AdminStatsPeriod.all:
        return null;
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  String _extractDomain(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'Sconosciuto';

    final normalized =
        trimmed.startsWith(RegExp(r'https?://')) ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(normalized);
    final host = uri?.host.toLowerCase() ?? '';
    if (host.startsWith('www.')) return host.substring(4);
    return host.isEmpty ? 'Sconosciuto' : host;
  }

  List<MapEntry<String, int>> _topEntries(Map<String, int> values,
      {int limit = 5}) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  bool _matchesFilters(_AdminUserRecord user) {
    final matchesRole = _roleFilter == null || user.role == _roleFilter;
    if (!matchesRole) return false;

    // ✅ NUOVO: Filtro marketing
    final matchesMarketing =
        _marketingFilter == null || user.acceptedMarketing == _marketingFilter;
    if (!matchesMarketing) return false;

    if (_searchQuery.isEmpty) return true;

    return user.email.toLowerCase().contains(_searchQuery) ||
        user.name.toLowerCase().contains(_searchQuery) ||
        (user.username?.toLowerCase().contains(_searchQuery) ?? false);
  }

  Future<void> _runUserAction(
    String userId,
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_updatingUserIds.contains(userId)) {
      return;
    }

    setState(() {
      _updatingUserIds.add(userId);
    });

    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingUserIds.remove(userId);
        });
      }
    }
  }

  Future<void> _updateUserRole(String userId, AppUserRole role) async {
    await _runUserAction(
      userId,
      () => AuthService().assignRoleToUserId(userId: userId, role: role),
      'Ruolo aggiornato a ${_roleLabel(role)}',
    );
  }

  Future<void> _updateDashboardRole(
    String userId,
    DashboardAccessRole dashboardRole,
  ) async {
    await _runUserAction(
      userId,
      () => AuthService().updateDashboardAccessRole(
        userId: userId,
        dashboardRole: dashboardRole,
      ),
      'Accesso dashboard aggiornato a ${_dashboardRoleLabel(dashboardRole)}',
    );
  }

  Future<void> _addDashboardAccess() async {
    final email = _dashboardAccessEmailController.text.trim();
    await _runUserAction(
      email.toLowerCase(),
      () => AuthService().upsertDashboardAccess(
        email: email,
        dashboardRole: _newDashboardAccessRole,
      ),
      'Accesso dashboard aggiunto per $email',
    );
    if (!mounted) return;
    _dashboardAccessEmailController.clear();
    setState(() {
      _newDashboardAccessRole = DashboardAccessRole.author;
      _accessesPage = 0;
    });
  }

  Future<void> _updateDashboardAccessRecord(
    _DashboardAccessRecord access,
    DashboardAccessRole dashboardRole,
  ) async {
    await _runUserAction(
      access.normalizedEmail,
      () => AuthService().updateDashboardAccessEmailRole(
        email: access.email,
        dashboardRole: dashboardRole,
      ),
      dashboardRole == DashboardAccessRole.none
          ? 'Accesso dashboard rimosso'
          : 'Accesso dashboard aggiornato a ${_dashboardRoleLabel(dashboardRole)}',
    );
  }

  Future<void> _toggleUserBlocked(_AdminUserRecord user) async {
    if (user.isBlocked) {
      await _unblockUsers([user]);
      return;
    }

    await _blockUsers([user], initialReason: user.blockedReason ?? '');
  }

  Future<void> _blockUsers(
    List<_AdminUserRecord> users, {
    String initialReason = '',
  }) async {
    if (!_canBlockUsers || users.isEmpty) return;

    final currentUserId = AuthService().currentUser?.id;
    final blockableUsers =
        users.where((user) => user.id != currentUserId).toList();
    if (blockableUsers.isEmpty) {
      _showAdminSnackBar(
        'Non puoi bloccare il tuo account admin.',
        isError: true,
      );
      return;
    }

    final reason = await _askBlockReason(
      count: blockableUsers.length,
      initialReason: initialReason,
    );
    if (reason == null) return;

    await _runBulkUserAction(
      users: blockableUsers,
      action: (user) => AuthService().updateUserBlockedState(
        userId: user.id,
        isBlocked: true,
        reason: reason,
      ),
      successMessage: blockableUsers.length == 1
          ? 'Utente bloccato'
          : '${blockableUsers.length} utenti bloccati',
    );
  }

  Future<void> _unblockUsers(List<_AdminUserRecord> users) async {
    if (!_canBlockUsers || users.isEmpty) return;

    final confirmed = await _confirmUnblockUsers(users.length);
    if (!confirmed) return;

    await _runBulkUserAction(
      users: users,
      action: (user) => AuthService().updateUserBlockedState(
        userId: user.id,
        isBlocked: false,
      ),
      successMessage: users.length == 1
          ? 'Utente sbloccato'
          : '${users.length} utenti sbloccati',
    );
  }

  Future<String?> _askBlockReason({
    required int count,
    String initialReason = '',
  }) {
    final controller = TextEditingController(text: initialReason);
    String? errorText;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title:
                  Text(count == 1 ? 'Blocca account' : 'Blocca $count utenti'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 1
                        ? 'Scrivi il messaggio che l’utente vedrà al prossimo accesso.'
                        : 'Scrivi il messaggio che questi utenti vedranno al prossimo accesso.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'Messaggio di blocco',
                      hintText: 'Es. Account sospeso per verifica...',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annulla'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final reason = controller.text.trim();
                    if (reason.isEmpty) {
                      setDialogState(() {
                        errorText =
                            'Inserisci il messaggio da mostrare all’utente.';
                      });
                      return;
                    }
                    Navigator.pop(context, reason);
                  },
                  icon: const Icon(Icons.block),
                  label: const Text('Blocca'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmUnblockUsers(int count) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title:
                Text(count == 1 ? 'Sblocca account' : 'Sblocca $count utenti'),
            content: Text(
              count == 1
                  ? 'Vuoi sbloccare questo account?'
                  : 'Vuoi sbloccare gli account selezionati?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.lock_open),
                label: const Text('Sblocca'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runBulkUserAction({
    required List<_AdminUserRecord> users,
    required Future<bool> Function(_AdminUserRecord user) action,
    required String successMessage,
  }) async {
    final ids = users.map((user) => user.id).toSet();
    setState(() {
      _updatingUserIds.addAll(ids);
    });

    try {
      for (final user in users) {
        await action(user);
      }
      if (!mounted) return;
      setState(() {
        _selectedUserIds.removeAll(ids);
      });
      _showAdminSnackBar(successMessage);
    } catch (e) {
      if (!mounted) return;
      _showAdminSnackBar(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingUserIds.removeAll(ids);
        });
      }
    }
  }

  void _showAdminSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _sendNotificationToSelected() async {
    if (!_canSendNotifications || _sendingNotification) return;

    final title = _notificationTitleController.text.trim();
    final body = _notificationBodyController.text.trim();
    final userIds = _selectedUserIds.toList();

    if (userIds.isEmpty) {
      _showAdminSnackBar('Seleziona almeno un utente.', isError: true);
      return;
    }
    if (title.isEmpty || body.isEmpty) {
      _showAdminSnackBar(
        'Titolo e messaggio della notifica sono obbligatori.',
        isError: true,
      );
      return;
    }
    if (!_sendInAppNotification && !_sendPushNotification) {
      _showAdminSnackBar('Scegli almeno un canale di invio.', isError: true);
      return;
    }

    setState(() {
      _sendingNotification = true;
    });

    try {
      int recipients = userIds.length;
      var pushSuccess = 0;
      var tokenCount = 0;
      final usedPushNotification = _sendPushNotification;

      if (usedPushNotification) {
        final callable = FirebaseFunctions.instance
            .httpsCallable('sendDashboardNotification');
        final result = await callable.call<Map<String, dynamic>>({
          'title': title,
          'body': body,
          'userIds': userIds,
          'sendInApp': _sendInAppNotification,
          'sendPush': true,
        });
        final data = result.data;
        recipients = data['recipients'] ?? userIds.length;
        pushSuccess = data['pushSuccessCount'] ?? 0;
        tokenCount = data['tokenCount'] ?? 0;
      } else {
        await _sendInAppNotificationDirectly(
          title: title,
          body: body,
          userIds: userIds,
        );
      }

      if (!mounted) return;
      _notificationTitleController.clear();
      _notificationBodyController.clear();
      setState(() {
        _selectedUserIds.clear();
        _sendInAppNotification = false;
        _sendPushNotification = false;
      });
      _showAdminSnackBar(
        usedPushNotification
            ? 'Notifica inviata a $recipients utenti. Push consegnate: $pushSuccess/$tokenCount.'
            : 'Notifica in-app inviata a $recipients utenti.',
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final details = e.details == null ? '' : ' (${e.details})';
      _showAdminSnackBar(
        'Errore notifiche: ${e.code} - ${e.message ?? 'nessun dettaglio'}$details',
        isError: true,
      );
    } catch (e) {
      if (!mounted) return;
      _showAdminSnackBar(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingNotification = false;
        });
      }
    }
  }

  Future<void> _sendEmailToSelected(StateSetter setLocalState) async {
    if (!_canSendNotifications || _sendingEmail) return;

    final subject = _emailSubjectController.text.trim();
    final emailBody = _emailBodyController.text.trim();
    final userIds = _selectedUserIds.toList();

    if (userIds.isEmpty) {
      _showAdminSnackBar('Seleziona almeno un utente.', isError: true);
      return;
    }
    if (subject.isEmpty) {
      _showAdminSnackBar("L'oggetto email è obbligatorio.", isError: true);
      return;
    }
    if (emailBody.isEmpty) {
      _showAdminSnackBar('Il corpo email è obbligatorio.', isError: true);
      return;
    }

    setLocalState(() => _sendingEmail = true);

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'sendBulkEmail',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'userIds': userIds,
        'subject': subject,
        'emailBody': emailBody,
      });
      final data = Map<String, dynamic>.from(result.data);
      final sent = data['sentCount'] ?? 0;
      final failed = data['failCount'] ?? 0;

      if (!mounted) return;
      _emailSubjectController.clear();
      _emailBodyController.clear();
      setLocalState(() {
        _sendingEmail = false;
        _emailTemplateIndex = 0;
      });
      setState(() => _selectedUserIds.clear());

      _showAdminSnackBar(
        failed == 0
            ? 'Email inviata a $sent utenti.'
            : 'Email inviata a $sent utenti. Fallite: $failed.',
        isError: failed > 0,
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setLocalState(() => _sendingEmail = false);
      _showAdminSnackBar(
        'Errore email: ${e.message ?? e.code}',
        isError: true,
      );
    } catch (e) {
      if (!mounted) return;
      setLocalState(() => _sendingEmail = false);
      _showAdminSnackBar(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  Future<void> _sendInAppNotificationDirectly({
    required String title,
    required String body,
    required List<String> userIds,
  }) async {
    final currentAdmin = AuthService().currentUser;
    final batch = _firestore.batch();
    final campaignId = _firestore.collection('users').doc().id;

    for (final userId in userIds) {
      final notificationRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc();
      batch.set(notificationRef, {
        'title': title,
        'body': body,
        'campaignId': campaignId,
        'createdAt': FieldValue.serverTimestamp(),
        'readAt': null,
        'senderId': currentAdmin?.id,
        'senderEmail': currentAdmin?.email,
      });
    }

    await batch.commit();
  }

  Future<_AdminUserCloudStats> _loadUserCloudStats(
    String userId,
    _AdminStatsPeriod period,
  ) async {
    final userRef = _firestore.collection('users').doc(userId);
    final periodStart = _statsPeriodStart(period);

    final postsSnapshot = await userRef.collection('posts').get();
    final foldersSnapshot = await userRef.collection('folders').get();
    final analyticsDoc =
        await userRef.collection('analytics').doc('summary').get();

    final folderNamesById = <String, String>{};
    for (final doc in foldersSnapshot.docs) {
      final data = doc.data();
      final name = (data['name'] as String?)?.trim();
      folderNamesById[doc.id] = name?.isNotEmpty == true ? name! : doc.id;
    }

    final allPosts = postsSnapshot.docs.map((doc) {
      final data = doc.data();
      return _AdminPostStatsRecord(
        id: doc.id,
        title: (data['title'] as String?)?.trim().isNotEmpty == true
            ? (data['title'] as String).trim()
            : 'Senza titolo',
        url: (data['url'] as String?)?.trim() ?? '',
        folderId: (data['folderId'] as String?)?.trim() ?? '',
        tags: List<String>.from(data['tags'] as List? ?? const []),
        createdAt: _parseDate(data['createdAt']),
      );
    }).toList();

    final filteredPosts = allPosts.where((post) {
      if (periodStart == null) return true;
      final createdAt = post.createdAt;
      return createdAt != null && !createdAt.isBefore(periodStart);
    }).toList();

    final filteredFolders = foldersSnapshot.docs.where((doc) {
      if (periodStart == null) return true;
      final createdAt = _parseDate(doc.data()['createdAt']);
      return createdAt != null && !createdAt.isBefore(periodStart);
    }).toList();

    final postsByDomain = <String, int>{};
    final postsByFolder = <String, int>{};
    final tags = <String, int>{};
    final postsByMonth = <String, int>{};
    DateTime? firstPostDate;
    DateTime? lastPostDate;

    for (final post in filteredPosts) {
      final domain = _extractDomain(post.url);
      postsByDomain[domain] = (postsByDomain[domain] ?? 0) + 1;

      final folderName = folderNamesById[post.folderId] ??
          (post.folderId.isNotEmpty ? post.folderId : 'Senza cartella');
      postsByFolder[folderName] = (postsByFolder[folderName] ?? 0) + 1;

      for (final rawTag in post.tags) {
        final tag = rawTag.toString().trim();
        if (tag.isEmpty) continue;
        tags[tag] = (tags[tag] ?? 0) + 1;
      }

      final createdAt = post.createdAt;
      if (createdAt != null) {
        final monthKey =
            '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}';
        postsByMonth[monthKey] = (postsByMonth[monthKey] ?? 0) + 1;

        if (firstPostDate == null || createdAt.isBefore(firstPostDate)) {
          firstPostDate = createdAt;
        }
        if (lastPostDate == null || createdAt.isAfter(lastPostDate)) {
          lastPostDate = createdAt;
        }
      }
    }

    final recentPosts = List<_AdminPostStatsRecord>.from(allPosts)
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    return _AdminUserCloudStats(
      period: period,
      totalPosts: allPosts.length,
      filteredPosts: filteredPosts.length,
      totalFolders: foldersSnapshot.docs.length,
      filteredFolders: filteredFolders.length,
      uniqueTags: tags.length,
      firstPostDate: firstPostDate,
      lastPostDate: lastPostDate,
      topDomains: _topEntries(postsByDomain),
      topFolders: _topEntries(postsByFolder),
      topTags: _topEntries(tags),
      postsByMonth: _topEntries(postsByMonth, limit: 12),
      recentPosts: recentPosts,
      syncedAnalytics: analyticsDoc.exists
          ? _AdminSyncedAnalytics.fromMap(analyticsDoc.data() ?? {})
          : null,
    );
  }

  Future<_AdminUserContentData> _loadUserContentData(String userId) async {
    final userRef = _firestore.collection('users').doc(userId);
    final postsSnapshot = await userRef.collection('posts').get();
    final foldersSnapshot = await userRef.collection('folders').get();

    final posts = postsSnapshot.docs.map((doc) {
      final data = doc.data();
      return _AdminPostStatsRecord(
        id: doc.id,
        title: (data['title'] as String?)?.trim().isNotEmpty == true
            ? (data['title'] as String).trim()
            : 'Senza titolo',
        url: (data['url'] as String?)?.trim() ?? '',
        folderId: (data['folderId'] as String?)?.trim() ?? '',
        tags: List<String>.from(data['tags'] as List? ?? const []),
        createdAt: _parseDate(data['createdAt']),
      );
    }).toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    final folders = foldersSnapshot.docs.map((doc) {
      final data = doc.data();
      return _AdminFolderStatsRecord(
        id: doc.id,
        name: (data['name'] as String?)?.trim().isNotEmpty == true
            ? (data['name'] as String).trim()
            : 'Senza nome',
        parentId: (data['parentId'] as String?)?.trim(),
        createdAt: _parseDate(data['createdAt']),
      );
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return _AdminUserContentData(posts: posts, folders: folders);
  }

  Future<_FinanceContentStats> _loadFinanceContentStats() async {
    final postsSnapshot = await _firestore.collectionGroup('posts').get();
    int postsWithPreview = 0;
    int postsWithRemotePreview = 0;

    for (final doc in postsSnapshot.docs) {
      final data = doc.data();
      final imageUrl = (data['imageUrl'] as String?)?.trim();
      final previewStorageUrl = (data['previewStorageUrl'] as String?)?.trim();
      if (imageUrl?.isNotEmpty == true ||
          previewStorageUrl?.isNotEmpty == true) {
        postsWithPreview++;
      }
      if (previewStorageUrl?.isNotEmpty == true) {
        postsWithRemotePreview++;
      }
    }

    return _FinanceContentStats(
      totalPosts: postsSnapshot.docs.length,
      postsWithPreview: postsWithPreview,
      postsWithRemotePreview: postsWithRemotePreview,
      estimatedPreviewBytes: postsWithPreview * _previewTargetBytes,
      estimatedFirestoreWrites: postsSnapshot.docs.length + postsWithPreview,
      estimatedUploadOperations: postsWithPreview,
    );
  }

  Future<_GlobalContentStats> _loadGlobalContentStats() async {
    final postsSnapshot = await _firestore.collectionGroup('posts').get();
    final foldersSnapshot = await _firestore.collectionGroup('folders').get();
    final postsBySource = <String, int>{};
    final postsByCreator = <String, int>{};
    final foldersByName = <String, int>{};

    for (final doc in postsSnapshot.docs) {
      final data = doc.data();
      final source = _extractDomain((data['url'] as String?)?.trim() ?? '');
      postsBySource[source] = (postsBySource[source] ?? 0) + 1;

      final creator = _creatorLabelFromPostData(data);
      if (creator != null) {
        postsByCreator[creator] = (postsByCreator[creator] ?? 0) + 1;
      }
    }

    for (final doc in foldersSnapshot.docs) {
      final data = doc.data();
      final rawName = (data['name'] as String?)?.trim();
      final folderName = rawName?.isNotEmpty == true ? rawName! : 'Senza nome';
      foldersByName[folderName] = (foldersByName[folderName] ?? 0) + 1;
    }

    return _GlobalContentStats(
      totalPosts: postsSnapshot.docs.length,
      totalFolders: foldersSnapshot.docs.length,
      topSources: _topEntries(postsBySource, limit: 10),
      topCreators: _topEntries(postsByCreator, limit: 30),
      topFolderNames: _topEntries(foldersByName, limit: 10),
    );
  }

  String? _creatorLabelFromPostData(Map<String, dynamic> data) {
    final creatorName = (data['creatorName'] as String?)?.trim();
    final creatorUsername = (data['creatorUsername'] as String?)?.trim();

    if (creatorUsername?.isNotEmpty == true &&
        creatorName?.isNotEmpty == true &&
        creatorName != creatorUsername) {
      return '$creatorName $creatorUsername';
    }
    if (creatorUsername?.isNotEmpty == true) return creatorUsername;
    if (creatorName?.isNotEmpty == true) return creatorName;
    return null;
  }

  Widget _buildStatCardsRow({required List<Widget> cards}) {
    const spacing = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minCardWidth = constraints.maxWidth < 760 ? 180.0 : 150.0;
        final canFitSingleRow = constraints.maxWidth >=
            cards.length * minCardWidth + (cards.length - 1) * spacing;

        if (!canFitSingleRow) {
          final cardWidth = constraints.maxWidth >= 520
              ? (constraints.maxWidth - spacing) / 2
              : constraints.maxWidth;

          return Wrap(
            alignment: WrapAlignment.center,
            spacing: spacing,
            runSpacing: spacing,
            children: cards
                .map((card) => SizedBox(width: cardWidth, child: card))
                .toList(),
          );
        }

        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: spacing),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  bool get _canGoBackFromAdminSection =>
      _activeSection != _AdminDashboardSection.users;

  void _goToDashboardHome() {
    setState(() {
      _activeSection = _AdminDashboardSection.users;
      _selectedUserId = null;
    });
  }

  void _openNotificationsSection() {
    setState(() {
      _activeSection = _AdminDashboardSection.notifications;
      _sendInAppNotification = false;
      _sendPushNotification = false;
    });
  }

  void _goBackFromAdminSection() {
    setState(() {
      if ((_activeSection == _AdminDashboardSection.userPosts ||
              _activeSection == _AdminDashboardSection.userFolders) &&
          _selectedUserId != null) {
        _activeSection = _AdminDashboardSection.userDetail;
        return;
      }

      _activeSection = _AdminDashboardSection.users;
      _selectedUserId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentAdmin = AuthService().currentUser;
    const adminBackground = Color(0xFFE6ECF5);
    const adminText = Color(0xFF111827);
    const adminMutedText = Color(0xFF4B5563);

    return Theme(
      data: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: adminBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: adminText,
              displayColor: adminText,
            ),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: adminMutedText),
          hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
          prefixIconColor: adminMutedText,
          border: OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.deepPurple, width: 2),
          ),
        ),
        dataTableTheme: DataTableThemeData(
          headingTextStyle: const TextStyle(
            color: adminText,
            fontWeight: FontWeight.w700,
          ),
          dataTextStyle: const TextStyle(color: adminText),
          headingRowColor: WidgetStatePropertyAll(Colors.grey.shade100),
        ),
      ),
      child: Scaffold(
        backgroundColor: adminBackground,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          shadowColor: const Color(0x22000000),
          toolbarHeight: 72,
          titleSpacing: 16,
          title: Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icon/app_icon_phone.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (_canGoBackFromAdminSection) ...[
                        _AdminBackButton(onPressed: _goBackFromAdminSection),
                        const SizedBox(width: 10),
                      ],
                      _AdminNavButton(
                        label: 'Home dashboard',
                        selected:
                            _activeSection == _AdminDashboardSection.users,
                        onPressed: _goToDashboardHome,
                      ),
                      if (_selectedUserId != null &&
                          (_activeSection ==
                                  _AdminDashboardSection.userDetail ||
                              _activeSection ==
                                  _AdminDashboardSection.userPosts ||
                              _activeSection ==
                                  _AdminDashboardSection.userFolders)) ...[
                        const SizedBox(width: 10),
                        _AdminNavButton(
                          label: 'Dettaglio utente',
                          selected: _activeSection ==
                              _AdminDashboardSection.userDetail,
                          onPressed: () {
                            setState(() {
                              _activeSection =
                                  _AdminDashboardSection.userDetail;
                            });
                          },
                        ),
                        const SizedBox(width: 10),
                        _AdminNavButton(
                          label: 'Post salvati',
                          selected: _activeSection ==
                              _AdminDashboardSection.userPosts,
                          onPressed: () {
                            setState(() {
                              _activeSection = _AdminDashboardSection.userPosts;
                              _postsPage = 0;
                              _postSourceFilter = null;
                            });
                          },
                        ),
                        const SizedBox(width: 10),
                        _AdminNavButton(
                          label: 'Cartelle',
                          selected: _activeSection ==
                              _AdminDashboardSection.userFolders,
                          onPressed: () {
                            setState(() {
                              _activeSection =
                                  _AdminDashboardSection.userFolders;
                              _foldersPage = 0;
                            });
                          },
                        ),
                      ],
                      const SizedBox(width: 10),
                      _AdminNavButton(
                        label: 'Piani Free/Premium',
                        selected:
                            _activeSection == _AdminDashboardSection.plans,
                        onPressed: () {
                          setState(() {
                            _activeSection = _AdminDashboardSection.plans;
                          });
                        },
                      ),
                      const SizedBox(width: 10),
                      _AdminNavButton(
                        label: 'Statistiche globali',
                        selected: _activeSection ==
                            _AdminDashboardSection.globalStats,
                        onPressed: () {
                          setState(() {
                            _activeSection = _AdminDashboardSection.globalStats;
                          });
                        },
                      ),
                      const SizedBox(width: 10),
                      _AdminNavButton(
                        label: 'Costi/Ricavi',
                        selected:
                            _activeSection == _AdminDashboardSection.finance,
                        onPressed: () {
                          setState(() {
                            _activeSection = _AdminDashboardSection.finance;
                          });
                        },
                      ),
                      const SizedBox(width: 10),
                      _AdminNavButton(
                        label: 'Notifiche',
                        selected: _activeSection ==
                            _AdminDashboardSection.notifications,
                        onPressed: _openNotificationsSection,
                      ),
                      const SizedBox(width: 10),
                      _AdminNavButton(
                        label: 'Accessi',
                        selected:
                            _activeSection == _AdminDashboardSection.accesses,
                        onPressed: () {
                          setState(() {
                            _activeSection = _AdminDashboardSection.accesses;
                            _accessesPage = 0;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await AuthService().logout();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: _activeSection == _AdminDashboardSection.plans
            ? _buildPlansInfoPage()
            : _activeSection == _AdminDashboardSection.globalStats
                ? _buildGlobalStatsPage()
                : _activeSection == _AdminDashboardSection.finance
                    ? _buildFinancePage()
                    : _activeSection == _AdminDashboardSection.notifications
                        ? _buildNotificationsPage()
                        : _activeSection == _AdminDashboardSection.accesses
                            ? _buildDashboardAccessPage()
                            : StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>>(
                                stream:
                                    _firestore.collection('users').snapshots(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                        child: CircularProgressIndicator());
                                  }

                                  if (snapshot.hasError) {
                                    return Center(
                                      child: Text(
                                        'Errore caricamento utenti: ${snapshot.error}',
                                        style:
                                            const TextStyle(color: adminText),
                                      ),
                                    );
                                  }

                                  final docs = snapshot.data?.docs ??
                                      <QueryDocumentSnapshot<
                                          Map<String, dynamic>>>[];
                                  final users = docs
                                      .map(_AdminUserRecord.fromDoc)
                                      .toList()
                                    ..sort((a, b) => a.email
                                        .toLowerCase()
                                        .compareTo(b.email.toLowerCase()));
                                  final filteredUsers =
                                      users.where(_matchesFilters).toList();

                                  final selectedUser = filteredUsers
                                      .cast<_AdminUserRecord?>()
                                      .firstWhere(
                                        (user) => user?.id == _selectedUserId,
                                        orElse: () => null,
                                      );

                                  final totalUsers = users.length;
                                  final freeUsers = users
                                      .where((user) =>
                                          user.role == AppUserRole.free)
                                      .length;
                                  final premiumUsers = users
                                      .where((user) =>
                                          user.role == AppUserRole.premium)
                                      .length;
                                  final adminUsers = users
                                      .where((user) =>
                                          user.role == AppUserRole.admin)
                                      .length;
                                  final blockedUsers = users
                                      .where((user) => user.isBlocked)
                                      .length;
                                  final marketingAcceptedUsers = users
                                      .where((user) => user.acceptedMarketing)
                                      .length;
                                  final marketingRejectedUsers =
                                      totalUsers - marketingAcceptedUsers;

                                  if (_activeSection ==
                                      _AdminDashboardSection.userDetail) {
                                    return _buildUserDetailPage(selectedUser);
                                  }
                                  if (_activeSection ==
                                      _AdminDashboardSection.userPosts) {
                                    return _buildUserPostsPage(selectedUser);
                                  }
                                  if (_activeSection ==
                                      _AdminDashboardSection.userFolders) {
                                    return _buildUserFoldersPage(selectedUser);
                                  }

                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxWidth: 1400),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildStatCardsRow(
                                              cards: [
                                                _StatCard(
                                                  label: 'Utenti totali',
                                                  value: '$totalUsers',
                                                  color: Colors.black87,
                                                ),
                                                _StatCard(
                                                  label: 'Free',
                                                  value: '$freeUsers',
                                                  color: Colors.grey.shade700,
                                                ),
                                                _StatCard(
                                                  label: 'Premium',
                                                  value: '$premiumUsers',
                                                  color: Colors.blue.shade700,
                                                ),
                                                _StatCard(
                                                  label: 'Admin',
                                                  value: '$adminUsers',
                                                  color: Colors
                                                      .deepPurple.shade700,
                                                ),
                                                _StatCard(
                                                  label: 'Bloccati',
                                                  value: '$blockedUsers',
                                                  color: Colors.red.shade700,
                                                ),
                                                _StatCard(
                                                  label: 'Marketing SI',
                                                  value:
                                                      '$marketingAcceptedUsers',
                                                  color:
                                                      Colors.green.shade700,
                                                ),
                                                _StatCard(
                                                  label: 'Marketing NO',
                                                  value:
                                                      '$marketingRejectedUsers',
                                                  color: Colors.orange.shade800,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            _buildUserFilters(currentAdmin),
                                            const SizedBox(height: 16),
                                            _buildUsersTable(filteredUsers),
                                            const SizedBox(height: 16),
                                            _buildRecentLogsPanel(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
      ),
    );
  }

  Widget _buildUsersTable(List<_AdminUserRecord> filteredUsers) {
    final maxPage = _maxPage(filteredUsers.length);
    if (_usersPage > maxPage) {
      _usersPage = maxPage;
    }
    final visibleUsers = _pageItems(filteredUsers, _usersPage);
    final selectedUsers = filteredUsers
        .where((user) => _selectedUserIds.contains(user.id))
        .toList();
    final selectedVisibleUsers = visibleUsers
        .where((user) => _selectedUserIds.contains(user.id))
        .toList();
    final allVisibleSelected = visibleUsers.isNotEmpty &&
        selectedVisibleUsers.length == visibleUsers.length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final title = Text(
                  'Utenti (${filteredUsers.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                );
                final actions = _buildUsersBulkActions(
                  selectedUsers: selectedUsers,
                  visibleUsers: visibleUsers,
                  allVisibleSelected: allVisibleSelected,
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      const SizedBox(height: 12),
                      actions,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: title),
                    actions,
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          if (filteredUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nessun utente trovato con i filtri attuali.'),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < 1100
                      ? 1280.0
                      : constraints.maxWidth;

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('')),
                          DataColumn(label: Text('Nome')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Marketing')), // ✅ NUOVO
                          DataColumn(label: Text('Ruolo')),
                          DataColumn(label: Text('Stato')),
                          DataColumn(label: Text('Creato il')),
                          DataColumn(label: Text('Ultimo login')),
                          DataColumn(label: Text('Azioni')),
                        ],
                        rows: visibleUsers.map((user) {
                          final selectedForBulk =
                              _selectedUserIds.contains(user.id);
                          return DataRow(
                            selected:
                                user.id == _selectedUserId || selectedForBulk,
                            color: WidgetStateProperty.resolveWith<Color?>(
                                (states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.deepPurple.shade50;
                              }
                              return null;
                            }),
                            onSelectChanged: (_) {
                              setState(() {
                                _selectedUserId = user.id;
                                _activeSection =
                                    _AdminDashboardSection.userDetail;
                              });
                            },
                            cells: [
                              DataCell(
                                Checkbox(
                                  value: selectedForBulk,
                                  onChanged: _canBlockUsers
                                      ? (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedUserIds.add(user.id);
                                            } else {
                                              _selectedUserIds.remove(user.id);
                                            }
                                          });
                                        }
                                      : null,
                                ),
                              ),
                              DataCell(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      user.name,
                                      style: const TextStyle(
                                        color: Color(0xFF111827),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      user.username ?? '-',
                                      style: TextStyle(
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                Text(
                                  user.email,
                                  style:
                                      const TextStyle(color: Color(0xFF111827)),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: user.acceptedMarketing
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    user.acceptedMarketing ? 'SI' : 'NO',
                                    style: TextStyle(
                                      color: user.acceptedMarketing
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(_RoleChip(
                                  role: user.role,
                                  color: _roleColor(user.role),
                                  label: _roleLabel(user.role))),
                              DataCell(
                                _StatusChip(
                                  label: user.isBlocked ? 'Bloccato' : 'Attivo',
                                  color: user.isBlocked
                                      ? Colors.red.shade700
                                      : Colors.green.shade700,
                                ),
                              ),
                              DataCell(
                                Text(
                                  _formatDate(user.createdAt),
                                  style:
                                      const TextStyle(color: Color(0xFF111827)),
                                ),
                              ),
                              DataCell(
                                Text(
                                  _formatDate(user.lastLogin),
                                  style:
                                      const TextStyle(color: Color(0xFF111827)),
                                ),
                              ),
                              DataCell(
                                OutlinedButton.icon(
                                  onPressed: !_canBlockUsers ||
                                          _updatingUserIds.contains(user.id)
                                      ? null
                                      : () => _toggleUserBlocked(user),
                                  icon: Icon(user.isBlocked
                                      ? Icons.lock_open
                                      : Icons.block),
                                  label: Text(
                                      user.isBlocked ? 'Sblocca' : 'Blocca'),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
            _PaginationControls(
              page: _usersPage,
              totalItems: filteredUsers.length,
              pageSize: _pageSize,
              onPrevious:
                  _usersPage == 0 ? null : () => setState(() => _usersPage--),
              onNext: _usersPage >= maxPage
                  ? null
                  : () => setState(() => _usersPage++),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUsersBulkActions({
    required List<_AdminUserRecord> selectedUsers,
    required List<_AdminUserRecord> visibleUsers,
    required bool allVisibleSelected,
  }) {
    final selectedCount = selectedUsers.length;
    final blockedSelected =
        selectedUsers.where((user) => user.isBlocked).toList();
    final activeSelected =
        selectedUsers.where((user) => !user.isBlocked).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          selectedCount == 0
              ? 'Seleziona utenti da bloccare o sbloccare'
              : '$selectedCount selezionati',
          style: const TextStyle(
            color: Color(0xFF4B5563),
            fontWeight: FontWeight.w600,
          ),
        ),
        OutlinedButton.icon(
          onPressed: !_canBlockUsers || visibleUsers.isEmpty
              ? null
              : () {
                  setState(() {
                    if (allVisibleSelected) {
                      for (final user in visibleUsers) {
                        _selectedUserIds.remove(user.id);
                      }
                    } else {
                      _selectedUserIds.addAll(
                        visibleUsers.map((user) => user.id),
                      );
                    }
                  });
                },
          icon: Icon(allVisibleSelected
              ? Icons.check_box
              : Icons.check_box_outline_blank),
          label: Text(
              allVisibleSelected ? 'Deseleziona pagina' : 'Seleziona pagina'),
        ),
        FilledButton.icon(
          onPressed: !_canBlockUsers || activeSelected.isEmpty
              ? null
              : () => _blockUsers(activeSelected),
          icon: const Icon(Icons.block),
          label: const Text('Blocca selezionati'),
        ),
        OutlinedButton.icon(
          onPressed: !_canBlockUsers || blockedSelected.isEmpty
              ? null
              : () => _unblockUsers(blockedSelected),
          icon: const Icon(Icons.lock_open),
          label: const Text('Sblocca selezionati'),
        ),
        FilledButton.icon(
          onPressed: !_canSendNotifications || selectedCount == 0
              ? null
              : _openNotificationsSection,
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Invia notifica'),
        ),
        TextButton(
          onPressed: selectedCount == 0
              ? null
              : () {
                  setState(_selectedUserIds.clear);
                },
          child: const Text('Pulisci selezione'),
        ),
      ],
    );
  }

  Widget _buildUserFilters(User? currentAdmin) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final search = TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Cerca utente',
              hintText: 'Email, nome o username',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          );
          final roleFilter = DropdownButtonFormField<AppUserRole?>(
            initialValue: _roleFilter,
            decoration: const InputDecoration(
              labelText: 'Filtro ruolo',
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<AppUserRole?>>[
              const DropdownMenuItem<AppUserRole?>(
                value: null,
                child: Text('Tutti i ruoli'),
              ),
              ...AppUserRole.values.map(
                (role) => DropdownMenuItem<AppUserRole?>(
                  value: role,
                  child: Text(_roleLabel(role)),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _roleFilter = value;
                _usersPage = 0;
              });
            },
          );
          final marketingFilter = DropdownButtonFormField<bool?>(
            initialValue: _marketingFilter,
            decoration: const InputDecoration(
              labelText: 'Filtro Marketing',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem<bool?>(
                value: null,
                child: Text('Tutti (Marketing)'),
              ),
              DropdownMenuItem<bool?>(
                value: true,
                child: Text('Solo Marketing SI'),
              ),
              DropdownMenuItem<bool?>(
                value: false,
                child: Text('Solo Marketing NO'),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _marketingFilter = value;
                _usersPage = 0;
              });
            },
          );
          final adminBadge = Container(
            width: compact ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.25)),
            ),
            child: Text(
              'Admin loggato: ${currentAdmin?.email ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 12),
                roleFilter,
                const SizedBox(height: 12),
                marketingFilter,
                const SizedBox(height: 12),
                adminBadge,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: search),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: roleFilter),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: marketingFilter),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: adminBadge),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlansInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Differenze tra Free e Premium',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pagina interna per supporto, onboarding e gestione commerciale dei piani SaveIn!.',
                style: TextStyle(
                  color: Color(0xFF4B5563),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final cards = [
                    _PlanComparisonCard(
                      title: 'Free',
                      subtitle: 'Per chi usa SaveIn! in modo leggero',
                      color: Colors.grey.shade700,
                      priceLabel: 'Gratis',
                      features: const [
                        _PlanFeature('Massimo 10 cartelle nella home', false),
                        _PlanFeature(
                            'Profondita cartelle: home + 1 livello', false),
                        _PlanFeature(
                            'Massimo 4 sottocartelle per cartella', false),
                        _PlanFeature(
                            'Salvataggio e organizzazione post/link', true),
                        _PlanFeature('Ricerca nei contenuti salvati', true),
                        _PlanFeature(
                            'Statistiche base disponibili nell’app', true),
                        _PlanFeature(
                            'Hashtag automatici se estratti dal contenuto',
                            true),
                        _PlanFeature(
                            'Aggiunta manuale hashtag non disponibile', false),
                        _PlanFeature('Annunci interstitial attivi', false),
                      ],
                    ),
                    _PlanComparisonCard(
                      title: 'Premium',
                      subtitle:
                          'Per utenti intensivi e organizzazione avanzata',
                      color: Colors.blue.shade700,
                      priceLabel: 'A pagamento',
                      features: const [
                        _PlanFeature('Cartelle home senza limite Free', true),
                        _PlanFeature(
                            'Profondita cartelle completa dell’app', true),
                        _PlanFeature('Sottocartelle senza limite Free', true),
                        _PlanFeature(
                            'Salvataggio e organizzazione post/link', true),
                        _PlanFeature('Ricerca nei contenuti salvati', true),
                        _PlanFeature('Statistiche base e avanzate', true),
                        _PlanFeature('Hashtag automatici e manuali', true),
                        _PlanFeature('Nessun annuncio interstitial', true),
                        _PlanFeature(
                            'Esperienza pensata per uso quotidiano', true),
                      ],
                    ),
                    _PlanComparisonCard(
                      title: 'Admin',
                      subtitle: 'Ruolo interno non acquistabile dagli utenti',
                      color: Colors.deepPurple.shade700,
                      priceLabel: 'Interno',
                      features: const [
                        _PlanFeature('Tutti i vantaggi Premium', true),
                        _PlanFeature('Accesso al pannello backend', true),
                        _PlanFeature('Gestione ruoli utenti', true),
                        _PlanFeature('Blocco e sblocco account', true),
                        _PlanFeature(
                            'Lettura statistiche utente da backend', true),
                        _PlanFeature(
                            'Non attivabile in autonomia dall’utente', true),
                      ],
                    ),
                  ];

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: cards
                          .map(
                            (card) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: card,
                              ),
                            ),
                          )
                          .toList(),
                    );
                  }

                  return Column(
                    children: cards
                        .map(
                          (card) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: card,
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Messaggio consigliato per upgrade',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Passa a Premium per organizzare liberamente i tuoi contenuti, creare piu livelli di cartelle, aggiungere hashtag manuali e usare SaveIn! senza annunci.',
                      style: TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        final users = (snapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map(_AdminUserRecord.fromDoc)
            .toList()
          ..sort(
              (a, b) => a.email.toLowerCase().compareTo(b.email.toLowerCase()));
        final selectedUsers =
            users.where((user) => _selectedUserIds.contains(user.id)).toList();
        final filteredUsers = users.where(_matchesFilters).toList();
        final maxPage = _maxPage(filteredUsers.length);
        if (_usersPage > maxPage) {
          _usersPage = maxPage;
        }
        final visibleUsers = _pageItems(filteredUsers, _usersPage);
        final selectedVisibleUsers = visibleUsers
            .where((user) => _selectedUserIds.contains(user.id))
            .toList();
        final allVisibleSelected = visibleUsers.isNotEmpty &&
            selectedVisibleUsers.length == visibleUsers.length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildUserFilters(AuthService().currentUser),
              const SizedBox(height: 16),
              _buildNotificationRecipientsPanel(
                snapshot: snapshot,
                filteredUsers: filteredUsers,
                visibleUsers: visibleUsers,
                selectedUsers: selectedUsers,
                allVisibleSelected: allVisibleSelected,
                maxPage: maxPage,
              ),
              const SizedBox(height: 16),
              _buildNotificationComposer(selectedUsers.length),
            ],
          ),
        );
      },
    );
  }

  static const List<Map<String, String>> _emailTemplates = [
    {'label': 'Personalizzato', 'subject': '', 'body': ''},
    {
      'label': 'Novita SaveIn!',
      'subject': 'Novita su SaveIn!',
      'body': 'Ciao,\n\nabbiamo preparato alcune novita che speriamo ti piaceranno!\n\n'
          '**Cosa c\'e di nuovo:**\n'
          '- [Descrivi novita 1]\n'
          '- [Descrivi novita 2]\n'
          '- [Descrivi novita 3]\n\n'
          'Apri l\'app per scoprire tutto.\n\n'
          'A presto,\nIl team SaveIn!',
    },
    {
      'label': 'Promo Premium',
      'subject': 'Passa a Premium',
      'body': 'Ciao,\n\nvuoi toglierti i limiti e dire addio alla pubblicita?\n\n'
          '**Con SaveIn! Premium ottieni:**\n'
          '- Cartelle illimitate\n'
          '- Sottocartelle senza limiti\n'
          '- Hashtag manuali\n'
          '- Nessuna pubblicita\n\n'
          'Passa a Premium dall\'app nella sezione Account.\n\n'
          'A presto,\nIl team SaveIn!',
    },
    {
      'label': 'Comunicazione',
      'subject': 'Comunicazione importante da SaveIn!',
      'body': 'Ciao,\n\nvolevamo aggiornarti su una novita importante riguardo SaveIn!.\n\n'
          '[Scrivi qui il testo della comunicazione]\n\n'
          'Per domande scrivi a support@savein.eu.\n\n'
          'Grazie,\nIl team SaveIn!',
    },
    {
      'label': 'Manutenzione',
      'subject': 'Manutenzione programmata - SaveIn!',
      'body': 'Ciao,\n\nti informiamo che SaveIn! sara temporaneamente non disponibile per manutenzione.\n\n'
          'Data: [inserisci data]\n'
          'Orario: [inserisci orario]\n\n'
          'Ci scusiamo per il disagio.\nIl team SaveIn!',
    },
  ];

  Widget _buildNotificationComposer(int selectedCount) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        void applyTemplate(int index) {
          _emailTemplateIndex = index;
          if (index > 0) {
            _emailSubjectController.text = _emailTemplates[index]['subject']!;
            _emailBodyController.text = _emailTemplates[index]['body']!;
          }
          setLocalState(() {});
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notifica',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'In-app appare come popup; push usa Firebase Cloud Messaging.',
                    style: TextStyle(color: Color(0xFF4B5563), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        selected: _sendInAppNotification,
                        label: const Text('In-app'),
                        avatar: const Icon(Icons.notifications_outlined),
                        onSelected: _sendingNotification
                            ? null
                            : (v) => setLocalState(() => _sendInAppNotification = v),
                      ),
                      FilterChip(
                        selected: _sendPushNotification,
                        label: const Text('Push fuori app'),
                        avatar: const Icon(Icons.phone_android),
                        onSelected: _sendingNotification
                            ? null
                            : (v) => setLocalState(() => _sendPushNotification = v),
                      ),
                      Chip(
                        avatar: const Icon(Icons.people_alt_outlined),
                        label: Text('$selectedCount selezionati'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notificationTitleController,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Titolo notifica',
                      hintText: 'Nuova funzione disponibile',
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notificationBodyController,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Messaggio',
                      hintText: 'Testo che l\'utente ricevera.',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.message_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: !_canSendNotifications ||
                            _sendingNotification ||
                            selectedCount == 0
                        ? null
                        : _sendNotificationToSelected,
                    icon: _sendingNotification
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(_sendingNotification ? 'Invio in corso...' : 'Invia notifica'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.email_outlined, color: Colors.blue, size: 22),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Invia Email',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      Chip(
                        avatar: const Icon(Icons.people_alt_outlined, size: 16),
                        label: Text('$selectedCount sel.'),
                        backgroundColor: Color(0xFFDBEAFE),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Email da noreply@savein.eu agli utenti selezionati. Usa **parola** per il grassetto.',
                    style: TextStyle(color: Color(0xFF4B5563), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  const Text('Template:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      _emailTemplates.length,
                      (i) => ChoiceChip(
                        label: Text(_emailTemplates[i]['label']!),
                        selected: _emailTemplateIndex == i,
                        onSelected: _sendingEmail ? null : (_) => applyTemplate(i),
                        selectedColor: const Color(0xFFBFDBFE),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailSubjectController,
                    maxLength: 150,
                    decoration: const InputDecoration(
                      labelText: 'Oggetto email',
                      hintText: 'Es: Novita su SaveIn!',
                      prefixIcon: Icon(Icons.subject),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailBodyController,
                    minLines: 6,
                    maxLines: 16,
                    maxLength: 3000,
                    decoration: const InputDecoration(
                      labelText: 'Corpo email',
                      hintText: 'Scrivi il testo.\nUsa **parola** per il grassetto.',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.text_snippet_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: !_canSendNotifications || _sendingEmail || selectedCount == 0
                        ? null
                        : () => _sendEmailToSelected(setLocalState),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1D4ED8)),
                    icon: _sendingEmail
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text(_sendingEmail
                        ? 'Invio email in corso...'
                        : 'Invia Email a $selectedCount utenti'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }


  Widget _buildNotificationRecipientsPanel({
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    required List<_AdminUserRecord> filteredUsers,
    required List<_AdminUserRecord> visibleUsers,
    required List<_AdminUserRecord> selectedUsers,
    required bool allVisibleSelected,
    required int maxPage,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Seleziona destinatari (${filteredUsers.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: !_canSendNotifications || visibleUsers.isEmpty
                      ? null
                      : () {
                          setState(() {
                            if (allVisibleSelected) {
                              for (final user in visibleUsers) {
                                _selectedUserIds.remove(user.id);
                              }
                            } else {
                              _selectedUserIds.addAll(
                                visibleUsers.map((user) => user.id),
                              );
                            }
                          });
                        },
                  icon: Icon(allVisibleSelected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank),
                  label: Text(allVisibleSelected
                      ? 'Deseleziona pagina'
                      : 'Seleziona pagina'),
                ),
                OutlinedButton.icon(
                  onPressed: !_canSendNotifications || filteredUsers.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _selectedUserIds.addAll(
                              filteredUsers
                                  .where((user) => user.acceptedMarketing)
                                  .map((user) => user.id),
                            );
                          });
                        },
                  icon: const Icon(Icons.mark_email_read_outlined),
                  label: const Text('Seleziona Marketing SI'),
                ),
                TextButton(
                  onPressed: selectedUsers.isEmpty
                      ? null
                      : () {
                          setState(_selectedUserIds.clear);
                        },
                  child: const Text('Pulisci selezione'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filteredUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nessun utente trovato.'),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < 1100
                      ? 1180.0
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('')),
                          DataColumn(label: Text('Nome')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Marketing')),
                          DataColumn(label: Text('Data consenso')),
                          DataColumn(label: Text('Ruolo')),
                          DataColumn(label: Text('Stato')),
                        ],
                        rows: visibleUsers.map((user) {
                          final selected = _selectedUserIds.contains(user.id);
                          return DataRow(
                            selected: selected,
                            color: WidgetStateProperty.resolveWith<Color?>(
                                (states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.deepPurple.shade50;
                              }
                              return null;
                            }),
                            cells: [
                              DataCell(
                                Checkbox(
                                  value: selected,
                                  onChanged: !_canSendNotifications
                                      ? null
                                      : (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedUserIds.add(user.id);
                                            } else {
                                              _selectedUserIds.remove(user.id);
                                            }
                                          });
                                        },
                                ),
                              ),
                              DataCell(Text(user.name)),
                              DataCell(Text(user.email)),
                              DataCell(_StatusChip(
                                label:
                                    user.acceptedMarketing ? 'SI' : 'NO',
                                color: user.acceptedMarketing
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              )),
                              DataCell(Text(
                                  _formatDate(user.marketingConsentDate))),
                              DataCell(_RoleChip(
                                role: user.role,
                                color: _roleColor(user.role),
                                label: _roleLabel(user.role),
                              )),
                              DataCell(_StatusChip(
                                label: user.isBlocked ? 'Bloccato' : 'Attivo',
                                color: user.isBlocked
                                    ? Colors.red.shade700
                                    : Colors.green.shade700,
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
            _PaginationControls(
              page: _usersPage,
              totalItems: filteredUsers.length,
              pageSize: _pageSize,
              onPrevious:
                  _usersPage == 0 ? null : () => setState(() => _usersPage--),
              onNext: _usersPage >= maxPage
                  ? null
                  : () => setState(() => _usersPage++),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDashboardAccessPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('dashboard_accesses').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Errore caricamento accessi: ${snapshot.error}'));
        }

        final accesses = (snapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map(_DashboardAccessRecord.fromDoc)
            .toList()
          ..sort((a, b) => a.email.compareTo(b.email));
        final dashboardAdminCount = accesses
            .where(
                (access) => access.dashboardRole == DashboardAccessRole.admin)
            .length;
        final maxPage = _maxPage(accesses.length);
        if (_accessesPage > maxPage) {
          _accessesPage = maxPage;
        }
        final visibleAccesses = _pageItems(accesses, _accessesPage);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Accessi dashboard',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Gestisci gli accessi al backend separati dagli utenti dell’app.',
                    style: TextStyle(color: Color(0xFF4B5563), fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  _buildDashboardAccessLegend(),
                  const SizedBox(height: 16),
                  _buildAddDashboardAccessPanel(),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final tableWidth = constraints.maxWidth < 1100
                            ? 1100.0
                            : constraints.maxWidth;

                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableWidth,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Email')),
                                DataColumn(label: Text('Accesso dashboard')),
                                DataColumn(label: Text('Aggiornato il')),
                                DataColumn(label: Text('Aggiornato da')),
                              ],
                              rows: visibleAccesses.map((access) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        access.email,
                                        style: const TextStyle(
                                          color: Color(0xFF111827),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: 210,
                                        child: DropdownButtonFormField<
                                            DashboardAccessRole>(
                                          value: access.dashboardRole,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            filled: true,
                                            fillColor: Color(0xFFF9FAFB),
                                            border: OutlineInputBorder(),
                                          ),
                                          items: DashboardAccessRole.values
                                              .map(
                                                (role) => DropdownMenuItem<
                                                    DashboardAccessRole>(
                                                  value: role,
                                                  child: Text(
                                                      _dashboardRoleLabel(
                                                          role)),
                                                ),
                                              )
                                              .toList(),
                                          onChanged:
                                              !_canManageDashboardAccess ||
                                                      _updatingUserIds.contains(
                                                          access
                                                              .normalizedEmail)
                                                  ? null
                                                  : (value) {
                                                      if (value == null ||
                                                          value ==
                                                              access
                                                                  .dashboardRole) {
                                                        return;
                                                      }
                                                      if (access.dashboardRole ==
                                                              DashboardAccessRole
                                                                  .admin &&
                                                          value !=
                                                              DashboardAccessRole
                                                                  .admin &&
                                                          dashboardAdminCount <=
                                                              1) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                                'non ci sono altri admin, non puoi non essercene uno'),
                                                            backgroundColor:
                                                                Colors.red,
                                                          ),
                                                        );
                                                        return;
                                                      }
                                                      _updateDashboardAccessRecord(
                                                        access,
                                                        value,
                                                      );
                                                    },
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                        Text(_formatDate(access.updatedAt))),
                                    DataCell(
                                        Text(access.updatedByEmail ?? '-')),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _PaginationControls(
                    page: _accessesPage,
                    totalItems: accesses.length,
                    pageSize: _pageSize,
                    onPrevious: _accessesPage == 0
                        ? null
                        : () => setState(() => _accessesPage--),
                    onNext: _accessesPage >= maxPage
                        ? null
                        : () => setState(() => _accessesPage++),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddDashboardAccessPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final emailField = TextField(
            controller: _dashboardAccessEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email accesso dashboard',
              hintText: 'nome@email.com',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
          );
          final roleField = DropdownButtonFormField<DashboardAccessRole>(
            value: _newDashboardAccessRole,
            decoration: const InputDecoration(
              labelText: 'Ruolo dashboard',
              border: OutlineInputBorder(),
            ),
            items: DashboardAccessRole.values
                .where((role) => role != DashboardAccessRole.none)
                .map(
                  (role) => DropdownMenuItem<DashboardAccessRole>(
                    value: role,
                    child: Text(_dashboardRoleLabel(role)),
                  ),
                )
                .toList(),
            onChanged: !_canManageDashboardAccess
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _newDashboardAccessRole = value;
                    });
                  },
          );
          final addButton = ElevatedButton.icon(
            onPressed: !_canManageDashboardAccess ? null : _addDashboardAccess,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Aggiungi accesso'),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Aggiungi utente dashboard',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                emailField,
                const SizedBox(height: 12),
                roleField,
                const SizedBox(height: 12),
                addButton,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aggiungi utente dashboard',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: emailField),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: roleField),
                  const SizedBox(width: 12),
                  SizedBox(height: 56, child: addButton),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGlobalStatsPage() {
    return FutureBuilder<_GlobalContentStats>(
      future: _loadGlobalContentStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Errore caricamento statistiche globali: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final stats = snapshot.data ?? const _GlobalContentStats.empty();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Statistiche globali',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Panoramica generale sui contenuti salvati da tutti gli utenti registrati.',
                    style: TextStyle(color: Color(0xFF4B5563), fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  _buildStatCardsRow(
                    cards: [
                      _StatCard(
                        label: 'Post analizzati',
                        value: '${stats.totalPosts}',
                        color: Colors.deepPurple.shade700,
                      ),
                      _StatCard(
                        label: 'Cartelle analizzate',
                        value: '${stats.totalFolders}',
                        color: Colors.blue.shade700,
                      ),
                      _StatCard(
                        label: 'Creator rilevati',
                        value: '${stats.topCreators.length}',
                        color: Colors.orange.shade800,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      final sources = _buildGlobalRankingPanel(
                        title: 'Top 10 provenienze',
                        subtitle:
                            'Social, domini o siti da cui gli utenti salvano più post.',
                        entries: stats.topSources,
                        emptyText: 'Nessuna provenienza trovata.',
                      );
                      final folders = _buildGlobalRankingPanel(
                        title: 'Cartelle più comuni',
                        subtitle:
                            'Nomi cartella più ripetuti tra tutti gli utenti.',
                        entries: stats.topFolderNames,
                        emptyText: 'Nessuna cartella trovata.',
                      );

                      if (!wide) {
                        return Column(
                          children: [
                            sources,
                            const SizedBox(height: 16),
                            folders,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: sources),
                          const SizedBox(width: 16),
                          Expanded(child: folders),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildGlobalRankingPanel(
                    title: 'Top 30 creator importati',
                    subtitle:
                        'Creator da cui tutti gli utenti hanno salvato più post. Il conteggio usa creatorName/creatorUsername quando disponibili.',
                    entries: stats.topCreators,
                    emptyText:
                        'Nessun creator rilevato nei post importati finora.',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlobalRankingPanel({
    required String title,
    required String subtitle,
    required List<MapEntry<String, int>> entries,
    required String emptyText,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Text(
              emptyText,
              style: const TextStyle(color: Color(0xFF6B7280)),
            )
          else
            ...entries.asMap().entries.map(
              (entry) {
                final rank = entry.key + 1;
                final item = entry.value;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          '$rank.',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.deepPurple.shade200,
                          ),
                        ),
                        child: Text(
                          '${item.value}',
                          style: TextStyle(
                            color: Colors.deepPurple.shade700,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFinancePage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Errore caricamento dati economici: ${snapshot.error}'),
          );
        }

        final users = (snapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .map(_AdminUserRecord.fromDoc)
            .toList();
        final freeUsers =
            users.where((user) => user.role == AppUserRole.free).length;
        final premiumUsers =
            users.where((user) => user.role == AppUserRole.premium).length;
        final totalUsers = users.length;

        final fixedCosts = _readMoney(_fixedCostsController);
        final freeUserCost = _readMoney(_freeUserCostController);
        final premiumUserCost = _readMoney(_premiumUserCostController);
        final premiumPrice = _readMoney(_premiumPriceController);
        final freeAdRevenue = _readMoney(_freeAdRevenueController);
        final paymentFeePercent = _readMoney(_paymentFeePercentController);

        final double premiumRevenue = premiumUsers * premiumPrice;
        final double adsRevenue = freeUsers * freeAdRevenue;
        final double totalRevenue = premiumRevenue + adsRevenue;
        final double freeCosts = freeUsers * freeUserCost;
        final double premiumCosts = premiumUsers * premiumUserCost;
        final double paymentFees = premiumRevenue * paymentFeePercent / 100;
        final double variableCosts = freeCosts + premiumCosts;
        final double totalCosts = fixedCosts + variableCosts + paymentFees;
        final double profit = totalRevenue - totalCosts;
        final double arpu = totalUsers == 0 ? 0.0 : totalRevenue / totalUsers;
        final double premiumNetMargin = premiumPrice -
            premiumUserCost -
            (premiumPrice * paymentFeePercent / 100);
        final double breakEvenPremiumUsers = premiumNetMargin <= 0
            ? 0.0
            : (fixedCosts + freeCosts - adsRevenue) / premiumNetMargin;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Costi, ricavi e guadagni',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Stima mensile basata sugli utenti reali presenti nel backend. Modifica i valori per simulare scenari diversi.',
                    style: TextStyle(color: Color(0xFF4B5563), fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  _buildStatCardsRow(
                    cards: [
                      _StatCard(
                        label: 'Utenti totali',
                        value: '$totalUsers',
                        color: Colors.black87,
                      ),
                      _StatCard(
                        label: 'Free',
                        value: '$freeUsers',
                        color: Colors.grey.shade700,
                      ),
                      _StatCard(
                        label: 'Premium',
                        value: '$premiumUsers',
                        color: Colors.blue.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 980;
                      final inputs = _buildFinanceInputs();
                      final results = _buildFinanceResults(
                        totalRevenue: totalRevenue,
                        totalCosts: totalCosts,
                        profit: profit,
                        premiumRevenue: premiumRevenue,
                        adsRevenue: adsRevenue,
                        fixedCosts: fixedCosts,
                        variableCosts: variableCosts,
                        paymentFees: paymentFees,
                        arpu: arpu,
                        breakEvenPremiumUsers: breakEvenPremiumUsers,
                      );

                      if (!wide) {
                        return Column(
                          children: [
                            inputs,
                            const SizedBox(height: 16),
                            results,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: inputs),
                          const SizedBox(width: 16),
                          Expanded(child: results),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildPreviewCostEstimator(),
                  const SizedBox(height: 16),
                  _buildFinanceNotes(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewCostEstimator() {
    return FutureBuilder<_FinanceContentStats>(
      future: _loadFinanceContentStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: const LinearProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Text(
              'Errore caricamento stima anteprime: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final stats = snapshot.data ?? const _FinanceContentStats.empty();
        final storagePercent =
            stats.estimatedPreviewBytes / _storageFreeBytes * 100;
        final downloadPercent =
            stats.estimatedPreviewBytes / _storageDownloadFreeBytes * 100;
        final uploadPercent =
            stats.estimatedUploadOperations / _storageUploadOpsFree * 100;
        final writesPercent =
            stats.estimatedFirestoreWrites / _firestoreWritesFreeDaily * 100;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Anteprime immagini e quote gratuite',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Stima basata sui post reali e sulla nuova compressione a circa 100 KB per anteprima. La cache locale riduce i download remoti dopo il primo caricamento.',
                style: TextStyle(color: Color(0xFF4B5563), fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _FinanceMetricCard(
                    label: 'Post totali',
                    value: '${stats.totalPosts}',
                    color: Colors.black87,
                  ),
                  _FinanceMetricCard(
                    label: 'Post con anteprima',
                    value: '${stats.postsWithPreview}',
                    color: Colors.blue.shade700,
                  ),
                  _FinanceMetricCard(
                    label: 'Anteprime remote',
                    value: '${stats.postsWithRemotePreview}',
                    color: Colors.deepPurple.shade700,
                  ),
                  _FinanceMetricCard(
                    label: 'Storage stimato',
                    value:
                        _formatDataSize(stats.estimatedPreviewBytes.toDouble()),
                    color: Colors.orange.shade800,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(
                label: 'Quota storage',
                value:
                    '${_formatPercent(storagePercent)} di 5 GB gratuiti Firebase Storage',
              ),
              _InfoRow(
                label: 'Download prima cache',
                value:
                    '${_formatDataSize(stats.estimatedPreviewBytes.toDouble())} se ogni anteprima viene scaricata una volta (${_formatPercent(downloadPercent)} di 100 GB/mese)',
              ),
              _InfoRow(
                label: 'Upload anteprime',
                value:
                    '${stats.estimatedUploadOperations} operazioni (${_formatPercent(uploadPercent)} di 5.000/mese)',
              ),
              _InfoRow(
                label: 'Scritture Firestore',
                value:
                    'circa ${stats.estimatedFirestoreWrites} (${_formatPercent(writesPercent)} di 20.000/giorno)',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFinanceInputs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Parametri mensili',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _FinanceInputField(
            controller: _fixedCostsController,
            label: 'Costi fissi mensili',
            helperText: 'Hosting, dominio, strumenti, servizi esterni',
          ),
          _FinanceInputField(
            controller: _freeUserCostController,
            label: 'Costo mensile per utente Free',
            helperText: 'Storage, Firestore, traffico, notifiche',
          ),
          _FinanceInputField(
            controller: _premiumUserCostController,
            label: 'Costo mensile per utente Premium',
            helperText: 'Uso medio maggiore di storage e letture',
          ),
          _FinanceInputField(
            controller: _premiumPriceController,
            label: 'Prezzo Premium mensile',
            helperText: 'Prezzo pagato dall’utente prima delle commissioni',
          ),
          _FinanceInputField(
            controller: _freeAdRevenueController,
            label: 'Ricavo ads medio per utente Free',
            helperText: 'Stima mensile media da pubblicità',
          ),
          _FinanceInputField(
            controller: _paymentFeePercentController,
            label: 'Commissioni pagamenti / store (%)',
            helperText: 'Percentuale trattenuta sui ricavi Premium',
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceResults({
    required double totalRevenue,
    required double totalCosts,
    required double profit,
    required double premiumRevenue,
    required double adsRevenue,
    required double fixedCosts,
    required double variableCosts,
    required double paymentFees,
    required double arpu,
    required double breakEvenPremiumUsers,
  }) {
    final profitColor =
        profit >= 0 ? Colors.green.shade700 : Colors.red.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Risultato stimato',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FinanceMetricCard(
                label: 'Ricavi mensili',
                value: _formatMoney(totalRevenue),
                color: Colors.blue.shade700,
              ),
              _FinanceMetricCard(
                label: 'Costi mensili',
                value: _formatMoney(totalCosts),
                color: Colors.orange.shade800,
              ),
              _FinanceMetricCard(
                label: 'Guadagno',
                value: _formatMoney(profit),
                color: profitColor,
              ),
              _FinanceMetricCard(
                label: 'ARPU',
                value: _formatMoney(arpu),
                color: Colors.deepPurple.shade700,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(
              label: 'Ricavi Premium', value: _formatMoney(premiumRevenue)),
          _InfoRow(label: 'Ricavi pubblicità', value: _formatMoney(adsRevenue)),
          _InfoRow(label: 'Costi fissi', value: _formatMoney(fixedCosts)),
          _InfoRow(
              label: 'Costi per utenza', value: _formatMoney(variableCosts)),
          _InfoRow(label: 'Commissioni', value: _formatMoney(paymentFees)),
          _InfoRow(
            label: 'Premium break-even',
            value: breakEvenPremiumUsers <= 0
                ? '0 utenti'
                : '${breakEvenPremiumUsers.ceil()} utenti',
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceNotes() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Come leggere questi numeri',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'I valori sono una simulazione mensile: i conteggi Free/Premium arrivano dal backend, mentre costi e prezzi sono modificabili. Il break-even indica quanti utenti Premium servono per coprire costi fissi, costi Free e commissioni, considerando anche i ricavi pubblicitari stimati.',
            style: TextStyle(color: Color(0xFF4B5563), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardAccessLegend() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _AccessLegendCard(
            title: 'Admin',
            color: Colors.deepPurple.shade700,
            description:
                'Può vedere tutto, modificare ruoli app, gestire accessi dashboard, bloccare/sbloccare utenti e compiere tutte le azioni amministrative.',
          ),
          _AccessLegendCard(
            title: 'Autore',
            color: Colors.indigo.shade700,
            description:
                'Può accedere alla dashboard solo in lettura: utenti, statistiche, piani e log. Non può modificare nulla.',
          ),
          _AccessLegendCard(
            title: 'Editore',
            color: Colors.orange.shade800,
            description:
                'Può visionare la dashboard e bloccare/sbloccare utenze. Non può cancellare utenti, modificare tipologia utente o gestire accessi dashboard.',
          ),
        ],
      ),
    );
  }

  Widget _buildUserDetailPage(_AdminUserRecord? user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user == null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Text(
                    'Utente non trovato. Torna alla dashboard e seleziona nuovamente un utente.',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else ...[
                Text(
                  'Dettaglio utente',
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gestione completa di ${user.email}',
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetailsPanel(user),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsPanel(_AdminUserRecord? user) {
    const primaryText = Color(0xFF111827);
    const secondaryText = Color(0xFF4B5563);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: user == null
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Seleziona un utente per vedere i dettagli.'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primaryText,
                        ),
                      ),
                    ),
                    _StatusChip(
                      label: user.isBlocked ? 'Bloccato' : 'Attivo',
                      color: user.isBlocked
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  user.email,
                  style: const TextStyle(
                    color: primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (user.username?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.username!,
                    style: const TextStyle(color: secondaryText),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _RoleChip(
                      role: user.role,
                      color: _roleColor(user.role),
                      label: _roleLabel(user.role),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<AppUserRole>(
                  value: user.role,
                  style: const TextStyle(
                    color: primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Ruolo utente',
                    labelStyle: TextStyle(color: secondaryText),
                    border: OutlineInputBorder(),
                  ),
                  items: AppUserRole.values
                      .map(
                        (role) => DropdownMenuItem<AppUserRole>(
                          value: role,
                          child: Text(
                            _roleLabel(role),
                            style: const TextStyle(color: primaryText),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _updatingUserIds.contains(user.id)
                      ? null
                      : !_canManageUserRoles
                          ? null
                          : (value) {
                              if (value == null || value == user.role) return;
                              _updateUserRole(user.id, value);
                            },
                ),
                const SizedBox(height: 16),
                _InfoRow(
                    label: 'Creato il', value: _formatDate(user.createdAt)),
                _InfoRow(
                    label: 'Ultimo login', value: _formatDate(user.lastLogin)),
                _InfoRow(
                  label: 'Motivo blocco',
                  value: user.blockedReason?.isNotEmpty == true
                      ? user.blockedReason!
                      : '-',
                ),
                _InfoRow(
                  label: 'Bloccato il',
                  value: _formatDate(user.blockedAt),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Consensi Marketing',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  label: 'Ricezione comunicazioni',
                  value: user.acceptedMarketing ? 'ACCETTATO' : 'NON ACCETTATO',
                  valueColor: user.acceptedMarketing ? Colors.green : Colors.red,
                ),
                _InfoRow(
                  label: 'Data conferma/disdetta',
                  value: _formatDate(user.marketingConsentDate),
                ),
                const SizedBox(height: 16),
                _buildUserStatsSection(user),
              ],
            ),
    );
  }

  Widget _buildUserStatsSection(_AdminUserRecord user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Statistiche utente',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<_AdminStatsPeriod>(
                  value: _statsPeriod,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Periodo',
                    labelStyle: TextStyle(color: Color(0xFF4B5563)),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _AdminStatsPeriod.values
                      .map(
                        (period) => DropdownMenuItem<_AdminStatsPeriod>(
                          value: period,
                          child: Text(
                            _statsPeriodLabel(period),
                            style: const TextStyle(color: Color(0xFF111827)),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _statsPeriod = value;
                      _statsPostsPage = 0;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<_AdminUserCloudStats>(
            future: _loadUserCloudStats(user.id, _statsPeriod),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }

              if (snapshot.hasError) {
                return Text(
                  'Errore caricamento statistiche: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                );
              }

              final stats = snapshot.data;
              if (stats == null) {
                return const Text(
                  'Nessuna statistica disponibile.',
                  style: TextStyle(color: Color(0xFF4B5563)),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: constraints.maxWidth < 880
                              ? 880
                              : constraints.maxWidth,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ClickableMiniStatCard(
                                label: 'Post salvati',
                                value: '${stats.totalPosts}',
                                icon: Icons.article_outlined,
                                onTap: () {
                                  setState(() {
                                    _selectedUserId = user.id;
                                    _activeSection =
                                        _AdminDashboardSection.userPosts;
                                    _postsPage = 0;
                                    _postSourceFilter = null;
                                  });
                                },
                              ),
                              const SizedBox(width: 12),
                              _ClickableMiniStatCard(
                                label: 'Cartelle',
                                value: '${stats.totalFolders}',
                                icon: Icons.folder_outlined,
                                onTap: () {
                                  setState(() {
                                    _selectedUserId = user.id;
                                    _activeSection =
                                        _AdminDashboardSection.userFolders;
                                    _foldersPage = 0;
                                  });
                                },
                              ),
                              const SizedBox(width: 12),
                              _MiniStatCard(
                                  label: 'Post nel periodo',
                                  value: '${stats.filteredPosts}'),
                              const SizedBox(width: 12),
                              _MiniStatCard(
                                  label: 'Post totali',
                                  value: '${stats.totalPosts}'),
                              const SizedBox(width: 12),
                              _MiniStatCard(
                                  label: 'Cartelle periodo',
                                  value: '${stats.filteredFolders}'),
                              const SizedBox(width: 12),
                              _MiniStatCard(
                                  label: 'Cartelle totali',
                                  value: '${stats.totalFolders}'),
                              const SizedBox(width: 12),
                              _MiniStatCard(
                                  label: 'Hashtag unici',
                                  value: '${stats.uniqueTags}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  _AdminSectionDivider(),
                  _InfoRow(
                    label: 'Primo post',
                    value: _formatDateOnly(stats.firstPostDate),
                  ),
                  _InfoRow(
                    label: 'Ultimo post',
                    value: _formatDateOnly(stats.lastPostDate),
                  ),
                  if (stats.syncedAnalytics != null) ...[
                    _AdminSectionDivider(),
                    const Text(
                      'Analytics app sincronizzate',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _MiniStatCard(
                          label: 'Aperture app',
                          value: '${stats.syncedAnalytics!.totalAppOpens}',
                        ),
                        _MiniStatCard(
                          label: 'Ricerche',
                          value: '${stats.syncedAnalytics!.totalSearches}',
                        ),
                        _MiniStatCard(
                          label: 'Post visti',
                          value: '${stats.syncedAnalytics!.totalPostsViewed}',
                        ),
                        _MiniStatCard(
                          label: 'Streak giorni',
                          value: '${stats.syncedAnalytics!.streakDays}',
                        ),
                        _MiniStatCard(
                          label: 'Tempo app',
                          value: stats.syncedAnalytics!.totalTimeLabel,
                        ),
                      ],
                    ),
                  ] else ...[
                    _AdminSectionDivider(),
                    const Text(
                      'Le statistiche locali dell’app (aperture, ricerche, tempo, streak) non sono ancora sincronizzate su Firestore per questo utente.',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                    ),
                  ],
                  _AdminSectionDivider(),
                  _buildBreakdownSection(
                      'Social / domini più salvati', stats.topDomains),
                  _AdminSectionDivider(),
                  _buildBreakdownSection(
                      'Cartelle più usate', stats.topFolders),
                  _AdminSectionDivider(),
                  _buildBreakdownSection('Hashtag più usati', stats.topTags),
                  _AdminSectionDivider(),
                  _buildBreakdownSection('Post per mese', stats.postsByMonth),
                  _AdminSectionDivider(),
                  _buildSavedPostsSection(stats.recentPosts),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownSection(
      String title, List<MapEntry<String, int>> entries) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          if (entries.isEmpty)
            const Text(
              'Nessun dato nel periodo selezionato.',
              style: TextStyle(color: Color(0xFF6B7280)),
            )
          else
            ...entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(color: Color(0xFF111827)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.value}',
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSavedPostsSection(List<_AdminPostStatsRecord> posts) {
    final maxPage = _maxPage(posts.length);
    if (_statsPostsPage > maxPage) {
      _statsPostsPage = maxPage;
    }
    final visiblePosts = _pageItems(posts, _statsPostsPage);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tutti i post salvati',
            style: TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          if (posts.isEmpty)
            const Text(
              'Nessun post salvato.',
              style: TextStyle(color: Color(0xFF6B7280)),
            )
          else
            ...visiblePosts.asMap().entries.map(
              (entry) {
                final post = entry.value;
                final index = _statsPostsPage * _pageSize + entry.key + 1;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildPostLinkRow(
                    post: post,
                    index: index,
                  ),
                );
              },
            ),
          if (posts.isNotEmpty)
            _PaginationControls(
              page: _statsPostsPage,
              totalItems: posts.length,
              pageSize: _pageSize,
              onPrevious: _statsPostsPage == 0
                  ? null
                  : () => setState(() => _statsPostsPage--),
              onNext: _statsPostsPage >= maxPage
                  ? null
                  : () => setState(() => _statsPostsPage++),
            ),
        ],
      ),
    );
  }

  Widget _buildUserPostsPage(_AdminUserRecord? user) {
    return _buildUserContentPageScaffold(
      title: 'Post salvati',
      subtitle: user == null
          ? 'Utente non trovato.'
          : 'Elenco dei post salvati da ${user.email}.',
      child: user == null
          ? const SizedBox.shrink()
          : FutureBuilder<_AdminUserContentData>(
              future: _loadUserContentData(user.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Text(
                    'Errore caricamento post: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                  );
                }

                final posts = snapshot.data?.posts ?? <_AdminPostStatsRecord>[];
                final sourceCounts = <String, int>{};
                for (final post in posts) {
                  final source = _extractDomain(post.url);
                  sourceCounts[source] = (sourceCounts[source] ?? 0) + 1;
                }
                final sourceEntries = sourceCounts.entries.toList()
                  ..sort((a, b) {
                    final countCompare = b.value.compareTo(a.value);
                    if (countCompare != 0) return countCompare;
                    return a.key.toLowerCase().compareTo(b.key.toLowerCase());
                  });
                final sources = posts
                    .map((post) => _extractDomain(post.url))
                    .toSet()
                    .toList()
                  ..sort();
                final filteredPosts = _postSourceFilter == null
                    ? posts
                    : posts
                        .where((post) =>
                            _extractDomain(post.url) == _postSourceFilter)
                        .toList();
                final maxPage = _maxPage(filteredPosts.length);
                if (_postsPage > maxPage) {
                  _postsPage = maxPage;
                }
                final visiblePosts = _pageItems(filteredPosts, _postsPage);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPostSourceCounts(
                      totalPosts: posts.length,
                      sourceEntries: sourceEntries,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      value: _postSourceFilter,
                      decoration: const InputDecoration(
                        labelText: 'Filtra per provenienza',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tutte le provenienze'),
                        ),
                        ...sources.map(
                          (source) => DropdownMenuItem<String?>(
                            value: source,
                            child: Text(source),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _postSourceFilter = value;
                          _postsPage = 0;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (visiblePosts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Nessun post trovato.'),
                      )
                    else
                      ...visiblePosts.asMap().entries.map(
                        (entry) {
                          final post = entry.value;
                          final index = _postsPage * _pageSize + entry.key + 1;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildPostLinkRow(
                              post: post,
                              index: index,
                            ),
                          );
                        },
                      ),
                    _PaginationControls(
                      page: _postsPage,
                      totalItems: filteredPosts.length,
                      pageSize: _pageSize,
                      onPrevious: _postsPage == 0
                          ? null
                          : () => setState(() => _postsPage--),
                      onNext: _postsPage >= maxPage
                          ? null
                          : () => setState(() => _postsPage++),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildPostSourceCounts({
    required int totalPosts,
    required List<MapEntry<String, int>> sourceEntries,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Conteggi per provenienza',
            style: TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PostSourceCountChip(
                label: 'Tutte',
                count: totalPosts,
                selected: _postSourceFilter == null,
                onTap: () {
                  setState(() {
                    _postSourceFilter = null;
                    _postsPage = 0;
                  });
                },
              ),
              ...sourceEntries.map(
                (entry) => _PostSourceCountChip(
                  label: entry.key,
                  count: entry.value,
                  selected: _postSourceFilter == entry.key,
                  onTap: () {
                    setState(() {
                      _postSourceFilter = entry.key;
                      _postsPage = 0;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserFoldersPage(_AdminUserRecord? user) {
    return _buildUserContentPageScaffold(
      title: 'Cartelle',
      subtitle: user == null
          ? 'Utente non trovato.'
          : 'Cartelle, sottocartelle e post salvati da ${user.email}.',
      child: user == null
          ? const SizedBox.shrink()
          : FutureBuilder<_AdminUserContentData>(
              future: _loadUserContentData(user.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) {
                  return Text(
                    'Errore caricamento cartelle: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                  );
                }

                final data = snapshot.data;
                final folders = data?.folders ?? <_AdminFolderStatsRecord>[];
                final posts = data?.posts ?? <_AdminPostStatsRecord>[];
                final rootFolders = folders
                    .where((folder) =>
                        folder.parentId == null || folder.parentId!.isEmpty)
                    .toList();
                final maxPage = _maxPage(rootFolders.length);
                if (_foldersPage > maxPage) {
                  _foldersPage = maxPage;
                }
                final visibleFolders = _pageItems(rootFolders, _foldersPage);

                if (visibleFolders.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessuna cartella trovata.'),
                  );
                }

                return Column(
                  children: [
                    ...visibleFolders.map(
                      (folder) => _buildFolderExpansionTile(
                        folder: folder,
                        allFolders: folders,
                        allPosts: posts,
                      ),
                    ),
                    _PaginationControls(
                      page: _foldersPage,
                      totalItems: rootFolders.length,
                      pageSize: _pageSize,
                      onPrevious: _foldersPage == 0
                          ? null
                          : () => setState(() => _foldersPage--),
                      onNext: _foldersPage >= maxPage
                          ? null
                          : () => setState(() => _foldersPage++),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildFolderExpansionTile({
    required _AdminFolderStatsRecord folder,
    required List<_AdminFolderStatsRecord> allFolders,
    required List<_AdminPostStatsRecord> allPosts,
    int depth = 0,
  }) {
    final childFolders = allFolders
        .where((child) => child.parentId == folder.id)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final folderPosts =
        allPosts.where((post) => post.folderId == folder.id).toList()
          ..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

    return StatefulBuilder(
      builder: (context, setFolderState) {
        final expanded = _expandedFolderIds.contains(folder.id);

        return Container(
          margin: EdgeInsets.only(left: depth * 16.0, bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setFolderState(() {
                    if (expanded) {
                      _expandedFolderIds.remove(folder.id);
                    } else {
                      _expandedFolderIds.add(folder.id);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_outlined,
                          color: Color(0xFF6D28D9)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    folder.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF111827),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _formatDateOnly(folder.createdAt),
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${childFolders.length} sottocartelle • ${folderPosts.length} post',
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: const Color(0xFF4B5563),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      const SizedBox(height: 10),
                      ...childFolders.map(
                        (child) => _buildFolderExpansionTile(
                          folder: child,
                          allFolders: allFolders,
                          allPosts: allPosts,
                          depth: depth + 1,
                        ),
                      ),
                      if (folderPosts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Nessun post in questa cartella.',
                              style: TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ),
                        )
                      else
                        ...folderPosts.map(_buildFolderPostRow),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFolderPostRow(_AdminPostStatsRecord post) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _buildPostLinkRow(post: post),
    );
  }

  Widget _buildPostLinkRow({
    required _AdminPostStatsRecord post,
    int? index,
  }) {
    final hasUrl = _postUri(post.url) != null;
    final titleColor =
        hasUrl ? Colors.deepPurple.shade700 : const Color(0xFF111827);
    final metaColor =
        hasUrl ? Colors.deepPurple.shade600 : const Color(0xFF4B5563);

    final row = Row(
      children: [
        if (index != null)
          SizedBox(
            width: 40,
            child: Text(
              '$index.',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else ...[
          Icon(
            Icons.article_outlined,
            size: 18,
            color:
                hasUrl ? Colors.deepPurple.shade700 : const Color(0xFF6B7280),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            post.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: titleColor,
              fontWeight: FontWeight.w700,
              decoration: hasUrl ? TextDecoration.underline : null,
            ),
          ),
        ),
        if (hasUrl) ...[
          const SizedBox(width: 8),
          Icon(Icons.open_in_new, size: 16, color: Colors.deepPurple.shade700),
        ],
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: Text(
            _formatDateOnly(post.createdAt),
            textAlign: TextAlign.right,
            style: TextStyle(color: metaColor, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 150,
          child: Text(
            _extractDomain(post.url),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(color: metaColor, fontSize: 12),
          ),
        ),
      ],
    );

    if (!hasUrl) {
      return row;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openPostUrl(post.url),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: row,
        ),
      ),
    );
  }

  Uri? _postUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final normalized =
        trimmed.startsWith(RegExp(r'https?://')) ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }

  Future<void> _openPostUrl(String rawUrl) async {
    final uri = _postUri(rawUrl);
    if (uri == null) return;

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire il link del post.')),
      );
    }
  }

  Widget _buildUserContentPageScaffold({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF4B5563), fontSize: 15),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentLogsPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Log admin recenti',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore
                .collection('admin_logs')
                .orderBy('timestamp', descending: true)
                .limit(15)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }

              if (snapshot.hasError) {
                return Text('Errore caricamento log: ${snapshot.error}');
              }

              final logs =
                  snapshot.data?.docs.map(_AdminLogRecord.fromDoc).toList() ??
                      <_AdminLogRecord>[];

              if (logs.isEmpty) {
                return const Text('Nessuna attività admin registrata.');
              }

              return Column(
                children: logs
                    .map(
                      (log) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Colors.blueGrey.shade50,
                          child:
                              const Icon(Icons.history, color: Colors.blueGrey),
                        ),
                        title: Text(log.title),
                        subtitle: Text(
                          '${log.actorEmail} • ${_formatDate(log.timestamp)}\n${log.subtitle}',
                        ),
                        isThreeLine: true,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStatCard({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 128,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSectionDivider extends StatelessWidget {
  const _AdminSectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Divider(height: 1, color: Color(0xFFE5E7EB)),
    );
  }
}

class _PostSourceCountChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _PostSourceCountChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : Colors.deepPurple.shade700;
    final background = selected ? Colors.deepPurple : const Color(0xFFF5F3FF);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? Colors.deepPurple : Colors.deepPurple.shade200,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.deepPurple.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClickableMiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _ClickableMiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 128,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.deepPurple.shade300, width: 1.4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: Colors.deepPurple.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.deepPurple.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaginationControls extends StatelessWidget {
  final int page;
  final int totalItems;
  final int pageSize;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _PaginationControls({
    required this.page,
    required this.totalItems,
    required this.pageSize,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final start = totalItems == 0 ? 0 : page * pageSize + 1;
    final end = (page * pageSize + pageSize).clamp(0, totalItems);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$start-$end di $totalItems',
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Precedenti'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Successivi'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? const Color(0xFF111827),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final AppUserRole role;
  final Color color;
  final String label;

  const _RoleChip({
    required this.role,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AdminNavButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _AdminNavButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFF374151);
    return Material(
      color: selected ? Colors.deepPurple : const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected ? Colors.deepPurple : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 44,
          constraints: const BoxConstraints(minWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AdminBackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.arrow_back,
            size: 20,
            color: Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}

class _PlanFeature {
  final String label;
  final bool included;

  const _PlanFeature(this.label, this.included);
}

class _PlanComparisonCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final String priceLabel;
  final List<_PlanFeature> features;

  const _PlanComparisonCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.priceLabel,
    required this.features,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  priceLabel,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          ...features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    feature.included ? Icons.check_circle : Icons.cancel,
                    color: feature.included
                        ? Colors.green.shade700
                        : Colors.red.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature.label,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String helperText;

  const _FinanceInputField({
    required this.controller,
    required this.label,
    required this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          prefixText: label.contains('%') ? null : '€ ',
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _FinanceMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _FinanceMetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessLegendCard extends StatelessWidget {
  final String title;
  final Color color;
  final String description;

  const _AccessLegendCard({
    required this.title,
    required this.color,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 350,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AdminDashboardSection {
  users,
  userDetail,
  userPosts,
  userFolders,
  plans,
  globalStats,
  finance,
  notifications,
  accesses,
}

enum _AdminStatsPeriod {
  last7Days,
  last30Days,
  last90Days,
  last365Days,
  all,
}

class _DashboardAccessRecord {
  final String id;
  final String email;
  final String normalizedEmail;
  final DashboardAccessRole dashboardRole;
  final DateTime? updatedAt;
  final String? updatedByEmail;

  const _DashboardAccessRecord({
    required this.id,
    required this.email,
    required this.normalizedEmail,
    required this.dashboardRole,
    required this.updatedAt,
    required this.updatedByEmail,
  });

  factory _DashboardAccessRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    final normalizedEmail =
        ((data['normalizedEmail'] as String?) ?? doc.id).toLowerCase().trim();
    return _DashboardAccessRecord(
      id: doc.id,
      email: ((data['email'] as String?) ?? normalizedEmail).trim(),
      normalizedEmail: normalizedEmail,
      dashboardRole:
          DashboardAccessRoleX.fromValue(data['dashboardRole'] as String?),
      updatedAt: parseDate(data['updatedAt'] ?? data['createdAt']),
      updatedByEmail: (data['updatedByEmail'] as String?)?.trim(),
    );
  }
}

class _FinanceContentStats {
  final int totalPosts;
  final int postsWithPreview;
  final int postsWithRemotePreview;
  final int estimatedPreviewBytes;
  final int estimatedFirestoreWrites;
  final int estimatedUploadOperations;

  const _FinanceContentStats({
    required this.totalPosts,
    required this.postsWithPreview,
    required this.postsWithRemotePreview,
    required this.estimatedPreviewBytes,
    required this.estimatedFirestoreWrites,
    required this.estimatedUploadOperations,
  });

  const _FinanceContentStats.empty()
      : totalPosts = 0,
        postsWithPreview = 0,
        postsWithRemotePreview = 0,
        estimatedPreviewBytes = 0,
        estimatedFirestoreWrites = 0,
        estimatedUploadOperations = 0;
}

class _GlobalContentStats {
  final int totalPosts;
  final int totalFolders;
  final List<MapEntry<String, int>> topSources;
  final List<MapEntry<String, int>> topCreators;
  final List<MapEntry<String, int>> topFolderNames;

  const _GlobalContentStats({
    required this.totalPosts,
    required this.totalFolders,
    required this.topSources,
    required this.topCreators,
    required this.topFolderNames,
  });

  const _GlobalContentStats.empty()
      : totalPosts = 0,
        totalFolders = 0,
        topSources = const [],
        topCreators = const [],
        topFolderNames = const [];
}

class _AdminUserCloudStats {
  final _AdminStatsPeriod period;
  final int totalPosts;
  final int filteredPosts;
  final int totalFolders;
  final int filteredFolders;
  final int uniqueTags;
  final DateTime? firstPostDate;
  final DateTime? lastPostDate;
  final List<MapEntry<String, int>> topDomains;
  final List<MapEntry<String, int>> topFolders;
  final List<MapEntry<String, int>> topTags;
  final List<MapEntry<String, int>> postsByMonth;
  final List<_AdminPostStatsRecord> recentPosts;
  final _AdminSyncedAnalytics? syncedAnalytics;

  const _AdminUserCloudStats({
    required this.period,
    required this.totalPosts,
    required this.filteredPosts,
    required this.totalFolders,
    required this.filteredFolders,
    required this.uniqueTags,
    required this.firstPostDate,
    required this.lastPostDate,
    required this.topDomains,
    required this.topFolders,
    required this.topTags,
    required this.postsByMonth,
    required this.recentPosts,
    required this.syncedAnalytics,
  });
}

class _AdminPostStatsRecord {
  final String id;
  final String title;
  final String url;
  final String folderId;
  final List<String> tags;
  final DateTime? createdAt;

  const _AdminPostStatsRecord({
    required this.id,
    required this.title,
    required this.url,
    required this.folderId,
    required this.tags,
    required this.createdAt,
  });
}

class _AdminFolderStatsRecord {
  final String id;
  final String name;
  final String? parentId;
  final DateTime? createdAt;

  const _AdminFolderStatsRecord({
    required this.id,
    required this.name,
    required this.parentId,
    required this.createdAt,
  });
}

class _AdminUserContentData {
  final List<_AdminPostStatsRecord> posts;
  final List<_AdminFolderStatsRecord> folders;

  const _AdminUserContentData({
    required this.posts,
    required this.folders,
  });
}

class _AdminSyncedAnalytics {
  final int totalAppOpens;
  final int totalSearches;
  final int totalPostsViewed;
  final int streakDays;
  final int totalTimeMinutes;

  const _AdminSyncedAnalytics({
    required this.totalAppOpens,
    required this.totalSearches,
    required this.totalPostsViewed,
    required this.streakDays,
    required this.totalTimeMinutes,
  });

  factory _AdminSyncedAnalytics.fromMap(Map<String, dynamic> data) {
    int readInt(String key) {
      final value = data[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _AdminSyncedAnalytics(
      totalAppOpens: readInt('totalAppOpens'),
      totalSearches: readInt('totalSearches'),
      totalPostsViewed: readInt('totalPostsViewed'),
      streakDays: readInt('streakDays'),
      totalTimeMinutes: readInt('totalTimeMinutes'),
    );
  }

  String get totalTimeLabel {
    final hours = totalTimeMinutes ~/ 60;
    final minutes = totalTimeMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }
}

class _AdminUserRecord {
  final String id;
  final String name;
  final String email;
  final String? username;
  final AppUserRole role;
  final DashboardAccessRole dashboardRole;
  final bool isBlocked;
  final String? blockedReason;
  final DateTime? blockedAt;
  final DateTime? createdAt;
  final DateTime? lastLogin;
  final bool acceptedMarketing;
  final DateTime? marketingConsentDate;

  const _AdminUserRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.username,
    required this.role,
    required this.dashboardRole,
    required this.isBlocked,
    required this.blockedReason,
    required this.blockedAt,
    required this.createdAt,
    required this.lastLogin,
    required this.acceptedMarketing,
    this.marketingConsentDate,
  });

  factory _AdminUserRecord.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    final consents = data['consents'] as Map<String, dynamic>?;
    final marketing = consents?['marketing'] as Map<String, dynamic>?;

    return _AdminUserRecord(
      id: doc.id,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String).trim()
          : 'Utente',
      email: (data['email'] as String?)?.trim() ?? '-',
      username: (data['username'] as String?)?.trim(),
      role: AppUserRoleX.fromValue(data['role'] as String?),
      dashboardRole:
          DashboardAccessRoleX.fromValue(data['dashboardRole'] as String?),
      isBlocked: data['isBlocked'] ?? false,
      blockedReason: data['blockedReason'] as String?,
      blockedAt: parseDate(data['blockedAt']),
      createdAt: parseDate(data['createdAt']),
      lastLogin: parseDate(data['lastLogin']),
      acceptedMarketing: marketing?['accepted'] ?? false,
      marketingConsentDate:
          parseDate(marketing?['lastModified']) ?? parseDate(marketing?['consentDate']),
    );
  }

  DashboardAccessRole get effectiveDashboardRole =>
      role == AppUserRole.admin ? DashboardAccessRole.admin : dashboardRole;
}

class _AdminLogRecord {
  final String action;
  final String actorEmail;
  final String targetUserId;
  final DateTime? timestamp;
  final Map<String, dynamic> details;

  const _AdminLogRecord({
    required this.action,
    required this.actorEmail,
    required this.targetUserId,
    required this.timestamp,
    required this.details,
  });

  factory _AdminLogRecord.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final timestampValue = data['timestamp'];

    return _AdminLogRecord(
      action: (data['action'] as String?) ?? 'unknown',
      actorEmail: (data['actorEmail'] as String?) ?? '-',
      targetUserId: (data['targetUserId'] as String?) ?? '-',
      timestamp: timestampValue is Timestamp ? timestampValue.toDate() : null,
      details:
          (data['details'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  String get title {
    switch (action) {
      case 'role_changed':
        return 'Ruolo utente aggiornato';
      case 'user_blocked':
        return 'Utente bloccato';
      case 'user_unblocked':
        return 'Utente sbloccato';
      case 'self_role_changed':
        return 'Cambio piano self-service';
      default:
        return action;
    }
  }

  String get subtitle {
    final newRole = details['newRole'];
    final reason = details['reason'];

    if (newRole != null) {
      return 'Target: $targetUserId • Nuovo ruolo: $newRole';
    }
    if (reason != null && reason.toString().trim().isNotEmpty) {
      return 'Target: $targetUserId • Motivo: $reason';
    }
    return 'Target: $targetUserId';
  }
}

