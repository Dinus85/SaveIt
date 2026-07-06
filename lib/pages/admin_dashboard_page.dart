import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;

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
  final TextEditingController _dashboardAccessPasswordController =
      TextEditingController();
  final TextEditingController _notificationTitleController =
      TextEditingController();
  final TextEditingController _notificationBodyController =
      TextEditingController();
  final TextEditingController _emailSubjectController = TextEditingController();
  final TextEditingController _emailBodyController = TextEditingController();

  String _searchQuery = '';
  AppUserRole? _roleFilter;
  bool? _marketingFilter;
  bool _birthdayThisWeekFilter = false;
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
  bool _systemCommunication = false;
  bool _sendingEmail = false;
  _NotificationMode _notificationMode = _NotificationMode.notification;
  int _emailTemplateIndex = 0;
  String? _selectedPromoId;
  String _selectedPromoType = 'birthday'; // 'birthday', 'banner'
  final Set<String> _expandedFolderIds = <String>{};
  final Set<String> _updatingUserIds = <String>{};
  final Set<String> _selectedUserIds = <String>{};
  static const int _pageSize = 20;
  static const int _previewTargetBytes = 100 * 1024;
  static const double _storageFreeBytes = 5 * 1024 * 1024 * 1024;
  static const double _storageDownloadFreeBytes = 100 * 1024 * 1024 * 1024;
  static const int _storageUploadOpsFree = 5000;
  static const int _firestoreWritesFreeDaily = 20000;
  static const String _centralPromoAdminUrl =
      'https://smart-chef-backend-514524345210.europe-west1.run.app/admin/promo-banners';
  Map<String, dynamic>? _planLimitsDraft;
  String? _planLimitsSnapshotKey;
  String? _planLimitsPendingSavedKey;
  bool _planLimitsDraftDirty = false;

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
    _dashboardAccessPasswordController.dispose();
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

  String _formatDateInput(DateTime? date) {
    if (date == null) return '';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  DateTime? _parseDateInput(String value, {bool endOfDay = false}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final italianParts = trimmed.split('/');
    if (italianParts.length == 3) {
      final day = int.tryParse(italianParts[0]);
      final month = int.tryParse(italianParts[1]);
      final year = int.tryParse(italianParts[2]);
      if (year == null || month == null || day == null) return null;
      return endOfDay
          ? DateTime(year, month, day, 23, 59, 59)
          : DateTime(year, month, day);
    }
    final parts = trimmed.split('-');
    if (parts.length != 3) return DateTime.tryParse(trimmed);
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return endOfDay
        ? DateTime(year, month, day, 23, 59, 59)
        : DateTime(year, month, day);
  }

  Future<void> _pickPromotionDate({
    required TextEditingController controller,
    required BuildContext dialogContext,
    required StateSetter setDialogState,
  }) async {
    final initialDate =
        _parseDateInput(controller.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: dialogContext,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      helpText: 'Seleziona data',
      cancelText: 'Annulla',
      confirmText: 'Conferma',
      fieldLabelText: 'Data',
      fieldHintText: 'gg/mm/aaaa',
    );
    if (picked == null) return;
    controller.text = _formatDateInput(picked);
    setDialogState(() {});
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
    if (user.isPlaceholder) return false;
    final matchesRole =
        _roleFilter == null || user.effectiveRole == _roleFilter;
    if (!matchesRole) return false;

    // ✅ NUOVO: Filtro marketing
    final matchesMarketing =
        _marketingFilter == null || user.acceptedMarketing == _marketingFilter;
    if (!matchesMarketing) return false;

    // ✅ NUOVO: Filtro compleanni della settimana
    if (_birthdayThisWeekFilter) {
      if (!_isBirthdayThisWeek(user.birthDate)) return false;
    }

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

  String _premiumExpiryLabel(_AdminUserRecord user) {
    if (user.role == AppUserRole.admin) return 'Admin';
    if (user.role != AppUserRole.premium) return '-';
    final premiumUntil = user.premiumUntil;
    if (premiumUntil == null) return 'Senza scadenza';
    final label = _formatDateOnly(premiumUntil);
    if (premiumUntil.isBefore(DateTime.now())) {
      return '$label (scaduta)';
    }
    return label;
  }

  Future<void> _editUserPremiumExpiry(_AdminUserRecord user) async {
    final controller =
        TextEditingController(text: _formatDateInput(user.premiumUntil));
    var saving = false;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Scadenza Premium'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.email,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Data fine Premium',
                    hintText: 'gg/mm/aaaa',
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onTap: saving
                      ? null
                      : () => _pickPromotionDate(
                            controller: controller,
                            dialogContext: dialogContext,
                            setDialogState: setDialogState,
                          ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La data viene salvata alle 00:00 del giorno selezionato. Se imposti una data, l’utente diventa Premium fino a quella scadenza.',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop('clear'),
              child: const Text('Rimuovi scadenza'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () {
                      setDialogState(() => saving = true);
                      Navigator.of(dialogContext).pop('save');
                    },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;

    if (action == 'clear') {
      await _runUserAction(
        user.id,
        () => AuthService().updateUserPremiumUntil(
          userId: user.id,
          premiumUntil: null,
        ),
        'Scadenza Premium rimossa',
      );
      return;
    }

    final parsed = _parseDateInput(controller.text.trim());
    if (parsed == null) {
      _showAdminSnackBar('Seleziona una data valida.', isError: true);
      return;
    }

    await _runUserAction(
      user.id,
      () => AuthService().updateUserPremiumUntil(
        userId: user.id,
        premiumUntil: parsed,
      ),
      'Scadenza Premium aggiornata',
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
    final password = _dashboardAccessPasswordController.text.trim();
    await _runUserAction(
      email.toLowerCase(),
      () => AuthService().upsertDashboardAccess(
        email: email,
        dashboardRole: _newDashboardAccessRole,
        password: password.isEmpty ? null : password,
      ),
      'Accesso dashboard aggiunto per $email',
    );
    if (!mounted) return;
    _dashboardAccessEmailController.clear();
    _dashboardAccessPasswordController.clear();
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

  bool _isBirthdayThisWeek(DateTime? birthDate) {
    if (birthDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final birthdayThisYear = DateTime(now.year, birthDate.month, birthDate.day);

    DateTime nextBirthday = birthdayThisYear;
    if (birthdayThisYear.isBefore(today)) {
      nextBirthday = DateTime(now.year + 1, birthDate.month, birthDate.day);
    }

    final difference = nextBirthday.difference(today).inDays;
    return difference >= 0 && difference <= 7;
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

  Future<void> _openCentralPromoAdmin() async {
    html.window.open(_centralPromoAdminUrl, '_blank');
  }

  void _showCentralPromoAdminRequired() {
    _showAdminSnackBar(
      'Le promo si attivano dalla gestione centrale SmartChef/SaveIn.',
      isError: true,
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
    final canProceed = await _confirmUsersWithoutCommunicationConsent(
      userIds: userIds,
      channelLabel: 'notifica',
    );
    if (!canProceed) return;

    setState(() {
      _sendingNotification = true;
    });

    try {
      int recipients = userIds.length;
      var pushSuccess = 0;
      var tokenCount = 0;
      final usedPushNotification = _sendPushNotification;

      final callable =
          FirebaseFunctions.instance.httpsCallable('sendDashboardNotification');
      final result = await callable.call<Map<String, dynamic>>({
        'title': title,
        'body': body,
        'userIds': userIds,
        'sendInApp': _sendInAppNotification,
        'sendPush': _sendPushNotification,
        'systemCommunication': _systemCommunication,
      });
      final data = result.data;
      recipients = data['recipients'] ?? userIds.length;
      pushSuccess = data['pushSuccessCount'] ?? 0;
      tokenCount = data['tokenCount'] ?? 0;
      final skippedConsent = data['skippedConsentCount'] ?? 0;

      if (!mounted) return;
      _notificationTitleController.clear();
      _notificationBodyController.clear();
      setState(() {
        _selectedUserIds.clear();
        _sendInAppNotification = false;
        _sendPushNotification = false;
        _systemCommunication = false;
      });
      _showAdminSnackBar(
        usedPushNotification
            ? 'Notifica inviata a $recipients utenti. Push consegnate: $pushSuccess/$tokenCount.${skippedConsent > 0 ? ' Saltati per consenso: $skippedConsent.' : ''}'
            : 'Notifica in-app inviata a $recipients utenti.${skippedConsent > 0 ? ' Saltati per consenso: $skippedConsent.' : ''}',
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
    final canProceed = await _confirmUsersWithoutCommunicationConsent(
      userIds: userIds,
      channelLabel: 'email',
    );
    if (!canProceed) return;

    setLocalState(() => _sendingEmail = true);

    try {
      final callable =
          FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
        'sendBulkEmail',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'userIds': userIds,
        'subject': subject,
        'emailBody': emailBody,
        'systemCommunication': _systemCommunication,
      });
      final data = Map<String, dynamic>.from(result.data);
      final sent = data['sentCount'] ?? 0;
      final failed = data['failCount'] ?? 0;
      final skippedConsent = data['skippedConsentCount'] ?? 0;

      if (!mounted) return;
      _emailSubjectController.clear();
      _emailBodyController.clear();
      setLocalState(() {
        _sendingEmail = false;
        _emailTemplateIndex = 0;
        _systemCommunication = false;
      });
      setState(() => _selectedUserIds.clear());

      _showAdminSnackBar(
        failed == 0
            ? 'Email inviata a $sent utenti.${skippedConsent > 0 ? ' Saltati per consenso: $skippedConsent.' : ''}'
            : 'Email inviata a $sent utenti. Fallite: $failed.${skippedConsent > 0 ? ' Saltati per consenso: $skippedConsent.' : ''}',
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

  Future<bool> _confirmUsersWithoutCommunicationConsent({
    required List<String> userIds,
    required String channelLabel,
  }) async {
    if (_systemCommunication) return true;

    var blockedCount = 0;
    final examples = <String>[];
    const chunkSize = 10;
    for (var i = 0; i < userIds.length; i += chunkSize) {
      final chunk = userIds.skip(i).take(chunkSize).toList();
      final snapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        final user = _AdminUserRecord.fromDoc(doc);
        if (user.acceptedMarketing) continue;
        blockedCount++;
        if (examples.length < 5) {
          examples.add(user.email);
        }
      }
    }

    if (blockedCount == 0 || !mounted) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
            SizedBox(width: 10),
            Expanded(child: Text('Consenso comunicazioni mancante')),
          ],
        ),
        content: Text(
          '$blockedCount utenti selezionati hanno NO alla ricezione comunicazioni.\n\n'
          'La $channelLabel non verrà inviata a questi utenti, a meno che tu non selezioni il flag:\n'
          '"Questa comunicazione deve arrivare sempre perché è di sistema".'
          '${examples.isEmpty ? '' : '\n\nEsempi:\n${examples.join('\n')}'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Continua saltando $blockedCount'),
          ),
        ],
      ),
    );
    return confirmed == true;
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
    final usersSnapshot = await _firestore.collection('users').get();
    final postsBySource = <String, int>{};
    final postsByCreator = <String, int>{};
    final tagsByName = <String, int>{};
    final foldersByName = <String, int>{};
    var freeUsers = 0;
    var premiumUsers = 0;
    var adminUsers = 0;

    for (final doc in postsSnapshot.docs) {
      final data = doc.data();
      final source = _extractDomain((data['url'] as String?)?.trim() ?? '');
      postsBySource[source] = (postsBySource[source] ?? 0) + 1;

      final creator = _creatorLabelFromPostData(data);
      if (creator != null) {
        postsByCreator[creator] = (postsByCreator[creator] ?? 0) + 1;
      }

      final tagsValue = data['tags'];
      if (tagsValue is Iterable) {
        for (final rawTag in tagsValue) {
          final tag = rawTag.toString().trim();
          if (tag.isEmpty) continue;
          tagsByName[tag] = (tagsByName[tag] ?? 0) + 1;
        }
      }
    }

    for (final doc in foldersSnapshot.docs) {
      final data = doc.data();
      final rawName = (data['name'] as String?)?.trim();
      final folderName = rawName?.isNotEmpty == true ? rawName! : 'Senza nome';
      foldersByName[folderName] = (foldersByName[folderName] ?? 0) + 1;
    }

    for (final doc in usersSnapshot.docs) {
      final user = _AdminUserRecord.fromDoc(doc);
      if (user.isPlaceholder) continue;
      if (user.role == AppUserRole.admin) {
        adminUsers++;
      } else if (user.role == AppUserRole.premium &&
          (user.premiumUntil == null ||
              !user.premiumUntil!.isBefore(DateTime.now()))) {
        premiumUsers++;
      } else {
        freeUsers++;
      }
    }

    return _GlobalContentStats(
      totalPosts: postsSnapshot.docs.length,
      totalFolders: foldersSnapshot.docs.length,
      totalUsers: freeUsers + premiumUsers + adminUsers,
      freeUsers: freeUsers,
      premiumUsers: premiumUsers,
      adminUsers: adminUsers,
      topSources: _topEntries(postsBySource, limit: 10),
      topCreators: _topEntries(postsByCreator, limit: 30),
      topTags: _topEntries(tagsByName, limit: 20),
      topFolderNames: _topEntries(foldersByName, limit: 20),
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

  Future<void> _showBulkBirthdayOfferDialog(
      List<_AdminUserRecord> users) async {
    final birthdayUsers =
        users.where((u) => _isBirthdayThisWeek(u.birthDate)).toList();
    if (birthdayUsers.isEmpty) {
      _showAdminSnackBar(
        'Seleziona almeno un utente con compleanno questa settimana.',
        isError: true,
      );
      return;
    }

    QuerySnapshot<Map<String, dynamic>> templatesSnapshot;
    try {
      templatesSnapshot = await _firestore
          .collection('birthday_offer_templates')
          .where('app_id', isEqualTo: 'savein')
          .get();
    } catch (e) {
      if (!mounted) return;
      _showAdminSnackBar(
        'Errore caricamento offerte compleanno: $e',
        isError: true,
      );
      return;
    }
    final templates = templatesSnapshot.docs
        .where((doc) => doc.data()['is_active'] != false)
        .toList();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Invia Offerta a ${birthdayUsers.length} utenti'),
        content: SizedBox(
          width: 460,
          child: templates.isEmpty
              ? const Text(
                  'Non ci sono offerte compleanno SaveIn configurate.\n\n'
                  'Creale dalla dashboard SmartChef in "Offerte Compleanno" scegliendo App Target: SaveIn.',
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Seleziona il tipo di offerta da inviare:'),
                    const SizedBox(height: 12),
                    ...templates.map((doc) {
                      final data = doc.data();
                      final premiumDays =
                          _readInt(data['premium_days'] ?? data['premiumDays']);
                      final promoCode = (data['promo_code'] as String?)?.trim();
                      final description =
                          (data['description'] as String?)?.trim();
                      final subtitleParts = <String>[
                        if (premiumDays > 0) '$premiumDays giorni Premium',
                        if (promoCode?.isNotEmpty == true) 'Codice: $promoCode',
                      ];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title:
                              Text((data['name'] as String?) ?? 'Senza nome'),
                          subtitle: Text(
                            subtitleParts.isEmpty
                                ? (description?.isNotEmpty == true
                                    ? description!
                                    : 'Offerta senza giorni Premium o codice promo')
                                : subtitleParts.join(' • '),
                          ),
                          trailing: const Icon(Icons.send),
                          onTap: () {
                            Navigator.pop(context);
                            _applyBulkBirthdayOffer(
                              birthdayUsers,
                              premiumDays: premiumDays,
                              promoCode: promoCode,
                              offerName: (data['name'] as String?) ??
                                  'Offerta compleanno',
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
        ],
      ),
    );
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _applyBulkBirthdayOffer(
    List<_AdminUserRecord> users, {
    required int premiumDays,
    String? promoCode,
    required String offerName,
  }) async {
    if (premiumDays <= 0 && (promoCode == null || promoCode.isEmpty)) {
      _showAdminSnackBar(
        'Questa offerta non ha giorni Premium né codice promo.',
        isError: true,
      );
      return;
    }

    int successCount = 0;
    for (final user in users) {
      try {
        if (premiumDays > 0) {
          final currentExpiry = user.premiumUntil ?? DateTime.now();
          final baseDate = currentExpiry.isAfter(DateTime.now())
              ? currentExpiry
              : DateTime.now();
          final newExpiry = baseDate.add(Duration(days: premiumDays));

          await AuthService().updateUserPremiumUntil(
            userId: user.id,
            premiumUntil: newExpiry,
          );
        }
        if (promoCode != null && promoCode.isNotEmpty) {
          await _firestore.collection('users').doc(user.id).set({
            'birthdayOffer': {
              'app_id': 'savein',
              'offerName': offerName,
              'promoCode': promoCode,
              'assignedAt': FieldValue.serverTimestamp(),
              'assignedBy': AuthService().currentUser?.id,
            },
          }, SetOptions(merge: true));
        }
        successCount++;
      } catch (e) {
        debugPrint('Errore invio offerta a ${user.email}: $e');
      }
    }

    if (!mounted) return;
    _showAdminSnackBar('Offerta "$offerName" inviata a $successCount utenti.');
    setState(() {
      _selectedUserIds.clear();
    });
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
                      _AdminNavButton(
                        label: 'Home dashboard',
                        selected:
                            _activeSection == _AdminDashboardSection.users ||
                                _activeSection ==
                                    _AdminDashboardSection.userDetail ||
                                _activeSection ==
                                    _AdminDashboardSection.userPosts ||
                                _activeSection ==
                                    _AdminDashboardSection.userFolders,
                        onPressed: _goToDashboardHome,
                      ),
                      const SizedBox(width: 10),
                      _AdminNavButton(
                        label: 'Banner promo',
                        selected:
                            _activeSection == _AdminDashboardSection.promos,
                        onPressed: _openCentralPromoAdmin,
                      ),
                      const SizedBox(width: 10),
                      _AdminNavButton(
                        label: 'Limiti Funzioni',
                        selected:
                            _activeSection == _AdminDashboardSection.planLimits,
                        onPressed: () {
                          setState(() {
                            _activeSection = _AdminDashboardSection.planLimits;
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
        body: _activeSection == _AdminDashboardSection.planLimits
            ? _buildPlanLimitsPage()
            : _activeSection == _AdminDashboardSection.globalStats
                ? _buildGlobalStatsPage()
                : _activeSection == _AdminDashboardSection.finance
                    ? _buildFinancePage()
                    : _activeSection == _AdminDashboardSection.notifications
                        ? _buildNotificationsPage()
                        : _activeSection == _AdminDashboardSection.promos
                            ? _buildCentralPromoRedirectPage()
                            : _activeSection == _AdminDashboardSection.accesses
                                ? _buildDashboardAccessPage()
                                : StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                    stream: _firestore
                                        .collection('users')
                                        .snapshots(),
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
                                            style: const TextStyle(
                                                color: adminText),
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
                                            (user) =>
                                                user?.id == _selectedUserId,
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
                                          .where(
                                              (user) => user.acceptedMarketing)
                                          .length;
                                      final marketingRejectedUsers =
                                          totalUsers - marketingAcceptedUsers;

                                      if (_activeSection ==
                                          _AdminDashboardSection.userDetail) {
                                        return _buildUserDetailPage(
                                            selectedUser);
                                      }
                                      if (_activeSection ==
                                          _AdminDashboardSection.userPosts) {
                                        return _buildUserPostsPage(
                                            selectedUser);
                                      }
                                      if (_activeSection ==
                                          _AdminDashboardSection.userFolders) {
                                        return _buildUserFoldersPage(
                                            selectedUser);
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
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                    _StatCard(
                                                      label: 'Premium',
                                                      value: '$premiumUsers',
                                                      color:
                                                          Colors.blue.shade700,
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
                                                      color:
                                                          Colors.red.shade700,
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
                                                      color: Colors
                                                          .orange.shade800,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 16),
                                                _buildBirthdayAlert(users),
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
      clipBehavior: Clip.hardEdge,
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
          _buildPromoBannerBar(selectedUsers),
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
                  final tableWidth = constraints.maxWidth < 1180
                      ? 1180.0
                      : constraints.maxWidth;

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.hardEdge,
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: tableWidth,
                      child: DataTable(
                        columnSpacing: 18,
                        horizontalMargin: 12,
                        headingRowHeight: 48,
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 58,
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('')),
                          DataColumn(label: Text('Nome')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Marketing')),
                          DataColumn(label: Text('Ruolo')),
                          DataColumn(label: Text('Piano Premium')),
                          DataColumn(label: Text('Stato')),
                          DataColumn(label: Text('Creato il')),
                          DataColumn(label: Text('Data nascita')),
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
                                SizedBox(
                                  width: 112,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              user.name,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF111827),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          if (_isBirthdayThisWeek(
                                              user.birthDate))
                                            Tooltip(
                                              message:
                                                  'Compleanno questa settimana',
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                    left: 4),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                  border: Border.all(
                                                    color: Colors.red.shade400,
                                                  ),
                                                ),
                                                child: const Text(
                                                  'BD',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Text(
                                        user.username ?? '-',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    user.email,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Color(0xFF111827)),
                                  ),
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
                              DataCell(
                                SizedBox(
                                    width: 70,
                                    child: _RoleChip(
                                      role: user.effectiveRole,
                                      color: _roleColor(user.effectiveRole),
                                      label: _roleLabel(user.effectiveRole),
                                    )),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    _premiumExpiryLabel(user),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: user.premiumUntil != null &&
                                              user.premiumUntil!
                                                  .isBefore(DateTime.now())
                                          ? Colors.red.shade700
                                          : const Color(0xFF111827),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                _StatusChip(
                                  label: user.isBlocked ? 'Bloccato' : 'Attivo',
                                  color: user.isBlocked
                                      ? Colors.red.shade700
                                      : Colors.green.shade700,
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 85,
                                  child: Text(
                                    _formatDate(user.createdAt),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Color(0xFF111827)),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 85,
                                  child: Text(
                                    _formatDateOnly(user.birthDate),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Color(0xFF111827)),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 80,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_isBirthdayThisWeek(user.birthDate))
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                            minHeight: 36,
                                          ),
                                          tooltip: 'Invia offerta compleanno',
                                          onPressed: () =>
                                              _showBulkBirthdayOfferDialog(
                                                  [user]),
                                          icon: const Icon(Icons.cake,
                                              color: Colors.orange, size: 20),
                                        ),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 36,
                                          minHeight: 36,
                                        ),
                                        tooltip: user.isBlocked
                                            ? 'Sblocca'
                                            : 'Blocca',
                                        onPressed: !_canBlockUsers ||
                                                _updatingUserIds
                                                    .contains(user.id)
                                            ? null
                                            : () => _toggleUserBlocked(user),
                                        icon: Icon(
                                          user.isBlocked
                                              ? Icons.lock_open
                                              : Icons.block,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
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
    final hasBirthdayOffer =
        selectedUsers.any((u) => _isBirthdayThisWeek(u.birthDate));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (selectedCount > 0 && hasBirthdayOffer)
          ElevatedButton.icon(
            onPressed: () => _showBulkBirthdayOfferDialog(selectedUsers),
            icon: const Icon(Icons.cake, size: 18),
            label: const Text('Invia Offerta Compleanno'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
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

  Widget _buildPromoBannerBar(List<_AdminUserRecord> selectedUsers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.yellow.shade50.withOpacity(0.5),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Invia Promo/Banner:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 430,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  _firestore.collection('birthday_offer_templates').snapshots(),
              builder: (context, birthdaySnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      _firestore.collection('promotion_banners').snapshots(),
                  builder: (context, bannersSnapshot) {
                    if (birthdaySnapshot.hasError || bannersSnapshot.hasError) {
                      return Text(
                        'Errore caricamento promo: ${birthdaySnapshot.error ?? bannersSnapshot.error}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                        ),
                      );
                    }
                    if (!birthdaySnapshot.hasData || !bannersSnapshot.hasData) {
                      return const Text('Caricamento promo...');
                    }

                    final birthdayDocs =
                        birthdaySnapshot.data!.docs.where((doc) {
                      final data = doc.data();
                      final appId = (data['app_id'] ?? data['appId'] ?? '')
                          .toString()
                          .toLowerCase();
                      final apps = data['apps'] as List? ?? const [];
                      return appId == 'savein' ||
                          appId == 'both' ||
                          apps.contains('savein');
                    }).toList();
                    final bannerDocs = bannersSnapshot.data!.docs.where((doc) {
                      final data = doc.data();
                      final apps = data['apps'] as List? ?? [];
                      final app = (data['app'] ?? '').toString().toLowerCase();
                      return app == 'savein' ||
                          app == 'both' ||
                          apps.contains('savein');
                    }).toList();

                    const placeholder = 'Scegli cosa inviare...';
                    final List<DropdownMenuItem<String>> items = [];

                    if (birthdayDocs.isNotEmpty) {
                      items.add(const DropdownMenuItem(
                        enabled: false,
                        child: _PromoDropdownHeader(
                          icon: Icons.cake_outlined,
                          label: 'Offerte Compleanno',
                        ),
                      ));
                      for (var doc in birthdayDocs) {
                        final data = doc.data();
                        final active = data['is_active'] != false &&
                            data['isActive'] != false &&
                            data['active'] != false;
                        items.add(DropdownMenuItem(
                          value: 'birthday:${doc.id}',
                          child: _PromoDropdownOption(
                            icon: Icons.card_giftcard_outlined,
                            title: data['name'] ?? 'Senza nome',
                            inactiveLabel: active ? null : 'non attiva in app',
                          ),
                        ));
                      }
                    }

                    if (bannerDocs.isNotEmpty) {
                      items.add(const DropdownMenuItem(
                        enabled: false,
                        child: _PromoDropdownHeader(
                          icon: Icons.campaign_outlined,
                          label: 'Banner SaveIn',
                        ),
                      ));
                      for (var doc in bannerDocs) {
                        final data = doc.data();
                        final active = data['active'] == true;
                        items.add(DropdownMenuItem(
                          value: 'banner:${doc.id}',
                          child: _PromoDropdownOption(
                            icon: Icons.local_offer_outlined,
                            title: data['title'] ?? doc.id,
                            inactiveLabel: active ? null : 'non attivo in app',
                          ),
                        ));
                      }
                    }

                    if (items.length == 1) {
                      return const Text(
                        'Nessuna promo SaveIn preparata trovata.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      );
                    }

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        height: 50,
                        padding: const EdgeInsets.only(left: 14, right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFEF7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.orange.shade500,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPromoId,
                            hint: const Text(
                              placeholder,
                              style: TextStyle(
                                color: Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            items: items,
                            isExpanded: true,
                            menuMaxHeight: 280,
                            icon: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.orange.shade300,
                                ),
                              ),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.orange.shade900,
                                size: 28,
                              ),
                            ),
                            selectedItemBuilder: (context) {
                              return items
                                  .where((item) => item.enabled)
                                  .map((item) => Align(
                                        alignment: Alignment.centerLeft,
                                        child: DefaultTextStyle.merge(
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          child: item.child,
                                        ),
                                      ))
                                  .toList();
                            },
                            onChanged: (val) {
                              setState(() {
                                _selectedPromoId = val;
                              });
                            },
                            style: const TextStyle(
                                fontSize: 14, color: Colors.black87),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: _selectedPromoId == null || selectedUsers.isEmpty
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: ElevatedButton(
              onPressed: _selectedPromoId == null || selectedUsers.isEmpty
                  ? null
                  : () => _sendSelectedPromo(selectedUsers),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow.shade700,
                foregroundColor: Colors.black87,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Invia ai selezionati',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 16),
          // Checkbox per filtrare i compleanni (come in SmartChef)
          Row(
            children: [
              Checkbox(
                value: _birthdayThisWeekFilter,
                mouseCursor: SystemMouseCursors.click,
                onChanged: (val) {
                  setState(() {
                    _birthdayThisWeekFilter = val ?? false;
                    if (_birthdayThisWeekFilter) {
                      _usersPage = 0;
                    }
                  });
                },
              ),
              const Text('Compleanni 7 giorni', style: TextStyle(fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sendSelectedPromo(List<_AdminUserRecord> users) async {
    if (_selectedPromoId == null) return;

    final parts = _selectedPromoId!.split(':');
    final type = parts[0];
    final id = parts[1];

    if (type == 'birthday') {
      // Usa la logica esistente per le offerte compleanno
      final doc =
          await _firestore.collection('birthday_offer_templates').doc(id).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final premiumDays = _readInt(data['premium_days'] ?? data['premiumDays']);
      final promoCode = (data['promo_code'] as String?)?.trim();
      final offerName = data['name'] ?? 'Offerta compleanno';

      await _applyBulkBirthdayOffer(
        users,
        premiumDays: premiumDays,
        promoCode: promoCode,
        offerName: offerName,
      );
    } else if (type == 'banner') {
      // Per i banner, inviamo una notifica che invita a vedere la promo
      final doc =
          await _firestore.collection('promotion_banners').doc(id).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final title = data['title'] ?? 'Nuova promo per te!';
      final body = data['message'] ?? 'Apri l\'app per scoprire i dettagli.';

      // Chiamiamo la funzione per inviare notifiche (in-app e push)
      try {
        final callable = FirebaseFunctions.instance
            .httpsCallable('sendDashboardNotification');
        await callable.call({
          'title': title,
          'body': body,
          'userIds': users.map((u) => u.id).toList(),
          'sendInApp': true,
          'sendPush': true,
        });

        _showAdminSnackBar(
            'Banner "$title" notificato a ${users.length} utenti.');
        setState(() {
          _selectedUserIds.clear();
          _selectedPromoId = null;
        });
      } catch (e) {
        _showAdminSnackBar('Errore invio notifica banner: $e', isError: true);
      }
    }
  }

  Widget _buildBirthdayAlert(List<_AdminUserRecord> users) {
    final birthdayUsers =
        users.where((u) => _isBirthdayThisWeek(u.birthDate)).toList();
    if (birthdayUsers.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.cake, color: Colors.orange, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎂 ${birthdayUsers.length} utenti compiono gli anni questa settimana!',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Text(
                  'Usa il filtro compleanni per vederli e inviare un\'offerta speciale.',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _birthdayThisWeekFilter = true;
                _usersPage = 0;
              });
            },
            child: const Text('Mostra utenti'),
          ),
        ],
      ),
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

          final birthdayFilter = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cake_outlined, size: 20, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('Compleanni settimana',
                    style: TextStyle(fontSize: 14)),
                Switch(
                  value: _birthdayThisWeekFilter,
                  activeColor: Colors.orange,
                  onChanged: (value) {
                    setState(() {
                      _birthdayThisWeekFilter = value;
                      _usersPage = 0;
                    });
                  },
                ),
              ],
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
                birthdayFilter,
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
              birthdayFilter,
              const SizedBox(width: 12),
              Expanded(flex: 2, child: adminBadge),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlanLimitsPage() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.doc('config/plan_limits').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Errore: ${snapshot.error}'));
        }

        final data = snapshot.data?.data() ?? {};
        final rawFeatureRules =
            data['featureRules'] as Map<String, dynamic>? ?? {};

        // Valori predefiniti dalla Bibbia del progetto
        final Map<String, dynamic> defaultRules = {
          'root_folders': {
            'free': {
              'enabled': true,
              'limit': 10,
              'period': 'total',
              'requiresAd': false
            },
            'premium': {
              'enabled': true,
              'limit': 0,
              'period': 'total',
              'requiresAd': false
            },
          },
          'child_folders': {
            'free': {
              'enabled': true,
              'limit': 4,
              'period': 'total',
              'requiresAd': false
            },
            'premium': {
              'enabled': true,
              'limit': 0,
              'period': 'total',
              'requiresAd': false
            },
          },
          'folder_levels': {
            'free': {
              'enabled': true,
              'limit': 1,
              'period': 'total',
              'requiresAd': false
            },
            'premium': {
              'enabled': true,
              'limit': 5,
              'period': 'total',
              'requiresAd': false
            },
          },
          'manual_tags': {
            'free': {
              'enabled': false,
              'limit': 0,
              'period': 'total',
              'requiresAd': false
            },
            'premium': {
              'enabled': true,
              'limit': 0,
              'period': 'total',
              'requiresAd': false
            },
          },
          'share_folder': {
            'free': {
              'enabled': true,
              'limit': 1,
              'period': 'day',
              'requiresAd': true
            },
            'premium': {
              'enabled': true,
              'limit': 0,
              'period': 'day',
              'requiresAd': false
            },
          },
          'share_post': {
            'free': {
              'enabled': true,
              'limit': 3,
              'period': 'day',
              'requiresAd': true
            },
            'premium': {
              'enabled': true,
              'limit': 0,
              'period': 'day',
              'requiresAd': false
            },
          },
          'import_shared': {
            'free': {
              'enabled': true,
              'limit': 5,
              'period': 'day',
              'requiresAd': true
            },
            'premium': {
              'enabled': true,
              'limit': 0,
              'period': 'day',
              'requiresAd': false
            },
          },
          'reminders': {
            'free': {
              'enabled': true,
              'limit': 0,
              'period': 'total',
              'requiresAd': true
            },
            'premium': {
              'enabled': true,
              'limit': 0,
              'period': 'total',
              'requiresAd': false
            },
          },
        };

        final snapshotKey = jsonEncode(rawFeatureRules);
        if (_planLimitsPendingSavedKey != null &&
            snapshotKey == _planLimitsPendingSavedKey) {
          _planLimitsPendingSavedKey = null;
          _planLimitsDraftDirty = false;
          _planLimitsSnapshotKey = snapshotKey;
          _planLimitsDraft = _mergedPlanLimitRules(
            rawFeatureRules,
            defaultRules,
          );
        } else if (_planLimitsDraft == null ||
            (_planLimitsPendingSavedKey == null &&
                !_planLimitsDraftDirty &&
                _planLimitsSnapshotKey != snapshotKey)) {
          _planLimitsSnapshotKey = snapshotKey;
          _planLimitsDraft = _mergedPlanLimitRules(
            rawFeatureRules,
            defaultRules,
          );
        }
        final featureRules = _planLimitsDraft!;

        final features = [
          {
            'id': 'root_folders',
            'name': 'Cartelle nella Home',
            'desc': 'Numero massimo di cartelle principali creabili nella Home.'
          },
          {
            'id': 'child_folders',
            'name': 'Sottocartelle per cartella',
            'desc': 'Numero massimo di sottocartelle per ogni cartella.'
          },
          {
            'id': 'folder_levels',
            'name': 'Livelli di profondità',
            'desc': 'Livelli massimi di annidamento (es. Home > L1 > L2...).'
          },
          {
            'id': 'manual_tags',
            'name': 'Tag manuali',
            'desc': 'Possibilità di aggiungere hashtag personalizzati ai post.'
          },
          {
            'id': 'share_folder',
            'name': 'Condivisione Cartella',
            'desc': 'Limite creazione link pubblici per intere cartelle.'
          },
          {
            'id': 'share_post',
            'name': 'Condivisione Post',
            'desc': 'Limite creazione link pubblici per singoli post.'
          },
          {
            'id': 'import_shared',
            'name': 'Importazione Contenuti',
            'desc':
                'Limite importazione contenuti condivisi da altri tramite link.'
          },
          {
            'id': 'reminders',
            'name': 'Reminder',
            'desc':
                'Impostazione e gestione reminder su post e cartelle, con eventuale pubblicità.'
          },
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configurazione Limiti Piani',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Gestisci i limiti di utilizzo per ogni funzionalità dell\'app.',
                            style: TextStyle(color: Color(0xFF4B5563)),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _planLimitsDraft =
                                    _deepCopyPlanLimitRules(defaultRules);
                                _planLimitsDraftDirty = true;
                              });
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Ripristina Predefiniti'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () => _savePlanLimits(featureRules),
                            icon: const Icon(Icons.save),
                            label: const Text('Salva Modifiche'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.2),
                        1: FlexColumnWidth(1),
                        2: FlexColumnWidth(1),
                      },
                      children: [
                        // Header
                        TableRow(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16)),
                          ),
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('Funzionalità',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Container(
                              padding: const EdgeInsets.all(20),
                              color: Colors.blue.shade50.withOpacity(0.3),
                              child: const Text('Piano FREE',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue)),
                            ),
                            Container(
                              padding: const EdgeInsets.all(20),
                              color: Colors.orange.shade50.withOpacity(0.3),
                              child: const Text('Piano PREMIUM',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange)),
                            ),
                          ],
                        ),
                        // Rows
                        ...features.map((f) {
                          final featId = f['id']!;
                          final featName = f['name']!;
                          final featDesc = f['desc']!;
                          return TableRow(
                            decoration: BoxDecoration(
                              border: Border(
                                  bottom:
                                      BorderSide(color: Colors.grey.shade100)),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(featName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text(featDesc,
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 13)),
                                    const SizedBox(height: 8),
                                    Text('ID: $featId',
                                        style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 11)),
                                  ],
                                ),
                              ),
                              _buildTierLimitCell(featureRules, featId, 'free'),
                              _buildTierLimitCell(
                                  featureRules, featId, 'premium'),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Map<String, dynamic> _deepCopyPlanLimitRules(Map<String, dynamic> source) {
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);
  }

  Map<String, dynamic> _mergedPlanLimitRules(
    Map<String, dynamic> source,
    Map<String, dynamic> defaults,
  ) {
    final rules = _deepCopyPlanLimitRules(source);
    defaults.forEach((key, value) {
      final defaultFeature = Map<String, dynamic>.from(value as Map);
      if (!rules.containsKey(key) || rules[key] is! Map) {
        rules[key] = _deepCopyPlanLimitRules(defaultFeature);
        return;
      }

      final feature = Map<String, dynamic>.from(rules[key] as Map);
      if (!feature.containsKey('free')) {
        feature['free'] = _deepCopyPlanLimitRules(
          Map<String, dynamic>.from(defaultFeature['free'] as Map),
        );
      }
      if (!feature.containsKey('premium')) {
        feature['premium'] = _deepCopyPlanLimitRules(
          Map<String, dynamic>.from(defaultFeature['premium'] as Map),
        );
      }
      rules[key] = feature;
    });
    return rules;
  }

  Widget _buildTierLimitCell(
      Map<String, dynamic> rules, String featureId, String tier) {
    Map<String, dynamic> tierRules() {
      if (rules[featureId] == null || rules[featureId] is! Map) {
        rules[featureId] = <String, dynamic>{};
      }
      final featureRules = rules[featureId] as Map<String, dynamic>;
      if (featureRules[tier] == null || featureRules[tier] is! Map) {
        featureRules[tier] = {
          'enabled': true,
          'limit': 0,
          'period': 'total',
          'requiresAd': false,
        };
      }
      return featureRules[tier] as Map<String, dynamic>;
    }

    return StatefulBuilder(
      builder: (context, setCellState) {
        final currentRules = tierRules();
        return Container(
          padding: const EdgeInsets.all(16),
          color: tier == 'free'
              ? Colors.blue.shade50.withOpacity(0.1)
              : Colors.orange.shade50.withOpacity(0.1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: currentRules['enabled'] ?? true,
                    onChanged: (val) {
                      setCellState(() {
                        tierRules()['enabled'] = val ?? false;
                        _planLimitsDraftDirty = true;
                      });
                    },
                  ),
                  const Text('Abilitato'),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Limite (0 = illimitato)',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              TextFormField(
                initialValue: (currentRules['limit'] ?? 0).toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) {
                  tierRules()['limit'] = int.tryParse(val) ?? 0;
                  _planLimitsDraftDirty = true;
                },
              ),
              const SizedBox(height: 12),
              const Text('Periodo reset', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: currentRules['period'] ?? 'total',
                isDense: true,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: const [
                  DropdownMenuItem(value: 'total', child: Text('Totale')),
                  DropdownMenuItem(value: 'day', child: Text('Giorno')),
                  DropdownMenuItem(value: 'week', child: Text('Settimana')),
                  DropdownMenuItem(value: 'month', child: Text('Mese')),
                ],
                onChanged: (val) {
                  setCellState(() {
                    tierRules()['period'] = val ?? 'total';
                    _planLimitsDraftDirty = true;
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: currentRules['requiresAd'] ?? false,
                    onChanged: (val) {
                      setCellState(() {
                        tierRules()['requiresAd'] = val ?? false;
                        _planLimitsDraftDirty = true;
                      });
                    },
                  ),
                  const Expanded(
                    child: Text(
                      'Richiede Pubblicità',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _savePlanLimits(Map<String, dynamic> rules) async {
    try {
      await _firestore.doc('config/plan_limits').set({
        'featureRules': rules,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': AuthService().currentUser?.email,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _planLimitsDraft = _deepCopyPlanLimitRules(rules);
          _planLimitsPendingSavedKey = jsonEncode(rules);
          _planLimitsDraftDirty = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Limiti salvati con successo!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante il salvataggio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildPlansInfoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
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
      'body':
          'Ciao,\n\nabbiamo preparato alcune novita che speriamo ti piaceranno!\n\n'
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
      'body':
          'Ciao,\n\nvuoi toglierti i limiti e dire addio alla pubblicita?\n\n'
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
      'body':
          'Ciao,\n\nvolevamo aggiornarti su una novita importante riguardo SaveIn!.\n\n'
              '[Scrivi qui il testo della comunicazione]\n\n'
              'Per domande scrivi a support@savein.eu.\n\n'
              'Grazie,\nIl team SaveIn!',
    },
    {
      'label': 'Manutenzione',
      'subject': 'Manutenzione programmata - SaveIn!',
      'body':
          'Ciao,\n\nti informiamo che SaveIn! sara temporaneamente non disponibile per manutenzione.\n\n'
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
            // Schede di selezione Tipo (Notifica vs Email)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade300, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setLocalState(() =>
                            _notificationMode = _NotificationMode.notification),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _notificationMode ==
                                    _NotificationMode.notification
                                ? Colors.purple.shade700
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _notificationMode ==
                                      _NotificationMode.notification
                                  ? Colors.purple.shade700
                                  : Colors.purple.shade100,
                              width: 1.6,
                            ),
                            boxShadow: _notificationMode ==
                                    _NotificationMode.notification
                                ? [
                                    BoxShadow(
                                      color: Colors.purple.withOpacity(0.24),
                                      blurRadius: 12,
                                      offset: const Offset(0, 5),
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_active_outlined,
                                color: _notificationMode ==
                                        _NotificationMode.notification
                                    ? Colors.white
                                    : Colors.purple.shade700,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Notifica Push / In-App',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: _notificationMode ==
                                          _NotificationMode.notification
                                      ? Colors.white
                                      : Colors.purple.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setLocalState(
                            () => _notificationMode = _NotificationMode.email),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _notificationMode == _NotificationMode.email
                                ? Colors.blue.shade700
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  _notificationMode == _NotificationMode.email
                                      ? Colors.blue.shade700
                                      : Colors.blue.shade100,
                              width: 1.6,
                            ),
                            boxShadow:
                                _notificationMode == _NotificationMode.email
                                    ? [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.22),
                                          blurRadius: 12,
                                          offset: const Offset(0, 5),
                                        )
                                      ]
                                    : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.email_outlined,
                                color:
                                    _notificationMode == _NotificationMode.email
                                        ? Colors.white
                                        : Colors.blue.shade700,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Email Marketing',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: _notificationMode ==
                                          _NotificationMode.email
                                      ? Colors.white
                                      : Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_notificationMode == _NotificationMode.notification)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.purple.shade200, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.shade50.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications_active_outlined,
                            color: Colors.purple, size: 22),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Configura Notifica',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        Chip(
                          avatar:
                              const Icon(Icons.people_alt_outlined, size: 16),
                          label: Text('$selectedCount selezionati'),
                          backgroundColor: Colors.purple.shade50,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'In-app appare come popup; push usa Firebase Cloud Messaging.',
                      style: TextStyle(color: Color(0xFF4B5563), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    _buildSystemCommunicationCheckbox(
                      setLocalState,
                      color: Colors.purple.shade700,
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
                              : (v) => setLocalState(
                                  () => _sendInAppNotification = v),
                        ),
                        FilterChip(
                          selected: _sendPushNotification,
                          label: const Text('Push fuori app'),
                          avatar: const Icon(Icons.phone_android),
                          onSelected: _sendingNotification
                              ? null
                              : (v) => setLocalState(
                                  () => _sendPushNotification = v),
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
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: !_canSendNotifications ||
                                _sendingNotification ||
                                selectedCount == 0
                            ? null
                            : _sendNotificationToSelected,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.purple.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: _sendingNotification
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send),
                        label: Text(_sendingNotification
                            ? 'Invio in corso...'
                            : 'Invia Notifica a $selectedCount utenti'),
                      ),
                    ),
                  ],
                ),
              ),

            if (_notificationMode == _NotificationMode.email)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade200, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade50.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.email_outlined,
                            color: Colors.blue, size: 22),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Configura Email',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        Chip(
                          avatar:
                              const Icon(Icons.people_alt_outlined, size: 16),
                          label: Text('$selectedCount selezionati'),
                          backgroundColor: Colors.blue.shade50,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Email da noreply@savein.eu agli utenti selezionati. Usa **parola** per il grassetto.',
                      style: TextStyle(color: Color(0xFF4B5563), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    _buildSystemCommunicationCheckbox(
                      setLocalState,
                      color: const Color(0xFF1D4ED8),
                    ),
                    const SizedBox(height: 16),
                    const Text('Template:',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        _emailTemplates.length,
                        (i) => ChoiceChip(
                          label: Text(_emailTemplates[i]['label']!),
                          selected: _emailTemplateIndex == i,
                          onSelected:
                              _sendingEmail ? null : (_) => applyTemplate(i),
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
                        hintText:
                            'Scrivi il testo.\nUsa **parola** per il grassetto.',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.text_snippet_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: !_canSendNotifications ||
                                _sendingEmail ||
                                selectedCount == 0
                            ? null
                            : () => _sendEmailToSelected(setLocalState),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1D4ED8),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: _sendingEmail
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send),
                        label: Text(_sendingEmail
                            ? 'Invio email in corso...'
                            : 'Invia Email a $selectedCount utenti'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSystemCommunicationCheckbox(
    StateSetter setLocalState, {
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: CheckboxListTile(
        value: _systemCommunication,
        onChanged: _sendingNotification || _sendingEmail
            ? null
            : (value) => setLocalState(() {
                  _systemCommunication = value ?? false;
                }),
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeColor: color,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'Questa comunicazione deve arrivare sempre perché è di sistema',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: const Text(
          'Se attivo, ignora il blocco marketing/comunicazioni per notifiche ed email istituzionali.',
        ),
      ),
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
                                label: user.acceptedMarketing ? 'SI' : 'NO',
                                color: user.acceptedMarketing
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              )),
                              DataCell(
                                  Text(_formatDate(user.marketingConsentDate))),
                              DataCell(_RoleChip(
                                role: user.effectiveRole,
                                color: _roleColor(user.effectiveRole),
                                label: _roleLabel(user.effectiveRole),
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
          final passwordField = TextField(
            controller: _dashboardAccessPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              hintText: 'Obbligatoria se l’utente non esiste',
              prefixIcon: Icon(Icons.lock_outline),
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
                passwordField,
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
                  Expanded(flex: 2, child: passwordField),
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

  // Vecchia pagina locale non piu' raggiungibile: la voce Banner promo ora
  // reindirizza sempre alla dashboard centrale SmartChef/SaveIn.
  // ignore: unused_element
  Widget _buildPromotionBannersPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('promotion_banners').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('Errore caricamento banner: ${snapshot.error}'));
        }

        final banners = (snapshot.data?.docs ?? [])
            .map(_PromotionBannerRecord.fromDoc)
            .toList()
          ..sort((a, b) => b.priority.compareTo(a.priority));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Banner promo centralizzati',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _openCentralPromoAdmin,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Apri gestione centrale'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _AdminInfoBox(
                title: 'Funzionamento',
                lines: const [
                  'Questa pagina resta come monitor locale dei banner che SaveIn riceve dal centro promo.',
                  'La creazione, modifica, attivazione, disattivazione ed eliminazione si fanno dalla gestione centrale SmartChef/SaveIn.',
                  'Per le cross promo puoi caricare due immagini: saveinImageUrl per SaveIn e smartchefImageUrl per SmartChef. imageUrl resta come fallback/generic.',
                  'Dimensioni immagine consigliate: 1200x400 px (formato 3:1). Alternativa accettabile: 1200x628 px, ma verra ritagliata/adattata.',
                  'type=cross_promo attiva la promo SaveIn/SmartChef; type=generic_promo apre un URL o mostra una proposta diversa.',
                  'Se oncePerUser=true, il banner sparisce dopo il primo utilizzo. Se la cross-promo e gia stata usata da una delle due app, non viene piu mostrata.',
                  'Può esserci una sola promo attiva alla volta: lo decide il centro promo e SaveIn riceve lo stato gia sincronizzato.',
                ],
              ),
              const SizedBox(height: 16),
              _buildNewSignupPremiumPromoSection(),
              const SizedBox(height: 12),
              _buildNewSignupPremiumPromoClaimsList(),
              const SizedBox(height: 16),
              _buildPromotionBannerSimpleList(banners),
              const SizedBox(height: 22),
              _buildPromotionBannerHistoryList(banners),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNewSignupPremiumPromoSection() {
    final docRef =
        _firestore.collection('app_config').doc('new_signup_premium_promo');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final active = data['active'] == true;
        final durationDays = (data['durationDays'] as num?)?.toInt() ?? 30;
        final priceAfterTrial = (data['priceAfterTrial'] ?? '2.99').toString();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.card_giftcard,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Promo nuovi iscritti',
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      active
                          ? 'Attiva: i nuovi iscritti Free possono accettare 1 mese Premium gratis. Prezzo comunicato dal secondo mese: €$priceAfterTrial.'
                          : 'Spenta: i nuovi iscritti non vedono la proposta Premium gratuita.',
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Durata prova: $durationDays giorni',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: active,
                onChanged: (value) async {
                  try {
                    await docRef.set({
                      'active': value,
                      'durationDays': 30,
                      'priceAfterTrial': '2.99',
                      'updatedAt': FieldValue.serverTimestamp(),
                      'updatedBy': AuthService().currentUser?.email,
                    }, SetOptions(merge: true));
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Impossibile aggiornare la promo: ${error.toString()}',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNewSignupPremiumPromoClaimsList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('new_signup_premium_promo_claims')
          .orderBy('startedAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Storico promo nuovi iscritti',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Elenco permanente delle email che hanno già usato la promo.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (docs.isEmpty)
                const Text(
                  'Nessuna attivazione registrata.',
                  style: TextStyle(color: Color(0xFF6B7280)),
                )
              else
                ...docs.map((doc) {
                  final data = doc.data();
                  final startedAt = _dateFromAny(data['startedAt']);
                  final premiumUntil = _dateFromAny(data['premiumUntil']);
                  final isActive = premiumUntil != null &&
                      premiumUntil.isAfter(DateTime.now());
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            (data['email'] ?? data['normalizedEmail'] ?? doc.id)
                                .toString(),
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Inizio: ${_formatDateOnly(startedAt)}',
                            style: const TextStyle(color: Color(0xFF4B5563)),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Fine: ${_formatDateOnly(premiumUntil)}',
                            style: const TextStyle(color: Color(0xFF4B5563)),
                          ),
                        ),
                        _StatusChip(
                          label: isActive ? 'Attiva' : 'Scaduta',
                          color: isActive
                              ? const Color(0xFF059669)
                              : const Color(0xFF6B7280),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  DateTime? _dateFromAny(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  Widget _buildPromotionBannerSimpleList(
    List<_PromotionBannerRecord> banners,
  ) {
    final now = DateTime.now();
    final activeBanners = banners.where((banner) {
      final ended = banner.endsAt != null && banner.endsAt!.isBefore(now);
      return banner.active && !ended;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Promo configurabili',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${activeBanners.length} attive',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCentralPromotionAdminCard(),
        const SizedBox(height: 12),
        if (activeBanners.isEmpty)
          const _AdminEmptyState(
            message:
                'Nessuna promo attiva. Le promo spente o scadute sono nello storico sotto.',
          )
        else
          for (final banner in activeBanners) ...[
            _PromotionBannerListRow(
              banner: banner,
              loadStats: _loadPromotionBannerStats,
              onToggle: (value) => _togglePromotionBanner(banner, value),
              onEdit: _openCentralPromoAdmin,
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _buildCentralPromoRedirectPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.hub_outlined,
              color: Color(0xFF2563EB),
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Gestione Centrale Banner e Promo',
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'La configurazione dei banner promozionali (cross-app e generici)\nè centralizzata nella dashboard SmartChef.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openCentralPromoAdmin,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Apri Dashboard Centrale (Nuova scheda)'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Nota: La gestione degli utenti SaveIn e l\'invio di offerte individuali\nrimane qui nella sezione "Home dashboard".',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCentralPromotionAdminCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub_outlined, color: Color(0xFF4338CA), size: 30),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestione centrale promo SmartChef/SaveIn',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Crea e attiva qui una sola promo globale alla volta, generica o cross-app.',
                  style: TextStyle(color: Color(0xFF4B5563), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _openCentralPromoAdmin,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Apri admin centrale'),
          ),
        ],
      ),
    );
  }

  // Rimasta come riferimento della vecchia UI locale; le promo ora si gestiscono
  // dalla dashboard centrale SmartChef/SaveIn.
  // ignore: unused_element
  Widget _buildPromotionQuickSetupCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PromotionSetupCard(
            title: 'Promo SaveIn + SmartChef',
            description:
                'Banner per attivare 30 giorni Premium e collegare le due app.',
            icon: Icons.local_fire_department,
            color: const Color(0xFFEA580C),
            onTap: () => _showPromotionBannerDialog(
              defaultId: 'savein_smartchef_launch',
              defaultType: 'cross_promo',
              lockType: true,
              defaultApp: 'both',
              defaultTitle: 'Promo lancio: SaveIn e SmartChef',
              defaultMessage:
                  'Attiva 30 giorni gratis di Premium e sblocca lo stesso vantaggio nell altra app usando la stessa email.',
              defaultCtaLabel: 'Attiva promo',
              defaultSecondaryCtaLabel: 'Apri altra app',
              defaultPriority: 100,
              defaultOncePerUser: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PromotionSetupCard(
            title: 'Promo generica SaveIn',
            description:
                'Banner con immagine, testo e link per offerte, inviti o campagne diverse.',
            icon: Icons.campaign_outlined,
            color: const Color(0xFF6D28D9),
            onTap: () => _showPromotionBannerDialog(
              defaultId: 'savein_generic_offer',
              defaultType: 'generic_promo',
              lockType: true,
              defaultApp: 'savein',
              defaultTitle: 'Promo disponibile',
              defaultMessage:
                  'Configura qui il testo della proposta mostrata agli utenti.',
              defaultCtaLabel: 'Scopri',
              defaultPriority: 10,
              defaultOncePerUser: false,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPromotionBannerHistoryList(
    List<_PromotionBannerRecord> banners,
  ) {
    final now = DateTime.now();
    final pastBanners = banners.where((banner) {
      final ended = banner.endsAt != null && banner.endsAt!.isBefore(now);
      return !banner.active || ended;
    }).toList()
      ..sort((a, b) {
        final aDate = a.endsAt ?? a.updatedAt ?? a.createdAt;
        final bDate = b.endsAt ?? b.updatedAt ?? b.createdAt;
        return (bDate ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(aDate ?? DateTime.fromMillisecondsSinceEpoch(0));
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Storico promo passate',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${pastBanners.length} promo',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Qui trovi le promo spente o scadute. Aprile per vedere periodo, dati e performance.',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (pastBanners.isEmpty)
          const _AdminEmptyState(
              message: 'Nessuna promo passata ancora presente.')
        else
          for (final banner in pastBanners) ...[
            _PromotionBannerHistoryTile(
              banner: banner,
              loadStats: _loadPromotionBannerStats,
              onReactivate: () => _reactivatePromotionBanner(banner),
              onEdit: _openCentralPromoAdmin,
              onDelete: () => _deletePromotionBanner(banner),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<_PromotionBannerStats> _loadPromotionBannerStats(String id) async {
    final events = await _firestore
        .collection('promotion_banner_events')
        .where('promotionId', isEqualTo: id)
        .get();
    final redemptions = await _firestore
        .collection('promotion_redemptions')
        .where('promotionId', isEqualTo: id)
        .get();

    var views = 0;
    var clicks = 0;
    for (final doc in events.docs) {
      final data = doc.data();
      final count = (data['count'] as num?)?.toInt() ?? 1;
      if (data['eventType'] == 'view') views += count;
      if (data['eventType'] == 'click') clicks += count;
    }
    return _PromotionBannerStats(
      views: views,
      clicks: clicks,
      redemptions: redemptions.size,
    );
  }

  Future<void> _togglePromotionBanner(
    _PromotionBannerRecord banner,
    bool active,
  ) async {
    _showCentralPromoAdminRequired();
  }

  Future<void> _deactivateOtherPromotionBanners(String keepActiveId) async {
    final activePromos = await _firestore
        .collection('promotion_banners')
        .where('active', isEqualTo: true)
        .get();
    final batch = _firestore.batch();
    var hasWrites = false;
    for (final doc in activePromos.docs) {
      if (doc.id == keepActiveId) continue;
      batch.set(
        doc.reference,
        {
          'active': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': AuthService().currentUser?.email,
        },
        SetOptions(merge: true),
      );
      hasWrites = true;
    }
    if (hasWrites) {
      await batch.commit();
    }
  }

  Future<void> _reactivatePromotionBanner(_PromotionBannerRecord banner) async {
    _showCentralPromoAdminRequired();
  }

  Future<void> _deletePromotionBanner(_PromotionBannerRecord banner) async {
    _showCentralPromoAdminRequired();
  }

  Future<void> _showPromotionBannerDialog({
    _PromotionBannerRecord? existing,
    String defaultId = '',
    String defaultType = 'generic_promo',
    String defaultApp = 'savein',
    String defaultTitle = '',
    String defaultMessage = '',
    String defaultCtaLabel = 'Scopri',
    String defaultSecondaryCtaLabel = '',
    String defaultActionUrl = '',
    int defaultPriority = 10,
    bool defaultOncePerUser = true,
    bool lockType = false,
  }) async {
    final idController = TextEditingController(text: existing?.id ?? defaultId);
    final titleController =
        TextEditingController(text: existing?.title ?? defaultTitle);
    final messageController =
        TextEditingController(text: existing?.message ?? defaultMessage);
    final ctaController =
        TextEditingController(text: existing?.ctaLabel ?? defaultCtaLabel);
    final secondaryController = TextEditingController(
        text: existing?.secondaryCtaLabel ?? defaultSecondaryCtaLabel);
    final urlController =
        TextEditingController(text: existing?.actionUrl ?? defaultActionUrl);
    final existingType = existing?.type ?? defaultType;
    final imageUrlController =
        TextEditingController(text: existing?.imageUrl ?? '');
    final saveInImageUrlController = TextEditingController(
        text: existing?.saveinImageUrl ??
            (existingType == 'cross_promo' || defaultApp == 'savein'
                ? existing?.imageUrl ?? ''
                : ''));
    final smartChefImageUrlController = TextEditingController(
        text: existing?.smartchefImageUrl ??
            (existingType == 'cross_promo' ? existing?.imageUrl ?? '' : ''));
    final priorityController = TextEditingController(
        text: (existing?.priority ?? defaultPriority).toString());
    final startsAtController =
        TextEditingController(text: _formatDateInput(existing?.startsAt));
    final endsAtController =
        TextEditingController(text: _formatDateInput(existing?.endsAt));
    var active = existing?.active ?? false;
    var oncePerUser = existing?.oncePerUser ?? defaultOncePerUser;
    var type = existing?.type ?? defaultType;
    var uploadingImage = false;

    bool isCrossPromoType() => type.trim() == 'cross_promo';

    Widget imageUrlEditor({
      required String label,
      required String helper,
      required TextEditingController controller,
      required String uploadSuffix,
      required StateSetter setDialogState,
    }) {
      return Column(
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: 'Consigliato 1200x400 px',
            ),
            onChanged: (_) => setDialogState(() {}),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: uploadingImage
                      ? null
                      : () async {
                          final docId = idController.text.trim().isEmpty
                              ? 'new_banner'
                              : idController.text.trim();
                          setDialogState(() => uploadingImage = true);
                          final uploadedUrl =
                              await _pickAndUploadPromotionBannerImage(
                            docId: '${docId}_$uploadSuffix',
                          );
                          if (uploadedUrl != null) {
                            controller.text = uploadedUrl;
                          }
                          setDialogState(() => uploadingImage = false);
                        },
                  icon: uploadingImage
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(
                    uploadingImage ? 'Caricamento...' : 'Carica immagine',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: uploadingImage
                      ? null
                      : () async {
                          final selectedUrl =
                              await _showPromotionBannerImageHistory();
                          if (selectedUrl != null) {
                            controller.text = selectedUrl;
                            setDialogState(() {});
                          }
                        },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Scegli dallo storico'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              helper,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (controller.text.trim().isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 3,
                child: Image.network(
                  controller.text.trim(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const Text('Anteprima non disponibile'),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title:
                  Text(existing == null ? 'Nuovo banner' : 'Modifica banner'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: idController,
                        enabled: existing == null,
                        decoration: const InputDecoration(
                          labelText: 'ID documento',
                          hintText: 'es. savein_generic_offer',
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!lockType) ...[
                        DropdownButtonFormField<String>(
                          value: type,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: const [
                            DropdownMenuItem(
                              value: 'cross_promo',
                              child: Text('cross_promo'),
                            ),
                            DropdownMenuItem(
                              value: 'generic_promo',
                              child: Text('generic_promo'),
                            ),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => type = value ?? type),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Titolo'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: messageController,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(labelText: 'Testo banner'),
                      ),
                      if (isCrossPromoType()) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: ctaController,
                          decoration: const InputDecoration(
                            labelText: 'Testo pulsante principale',
                            hintText: 'Es. Scopri, Attiva promo, Avvia',
                          ),
                        ),
                      ],
                      if (isCrossPromoType()) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: secondaryController,
                          decoration: const InputDecoration(
                            labelText: 'Testo pulsante secondario',
                            hintText: 'Opzionale',
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: urlController,
                        decoration: const InputDecoration(
                          labelText: 'URL azione (per generic_promo)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (type == 'generic_promo') ...[
                        imageUrlEditor(
                          label: 'URL immagine generic promo',
                          helper:
                              'Immagine mostrata per la promo generica. Questo e l’unico banner usato per generic_promo.',
                          controller: imageUrlController,
                          uploadSuffix: 'generic',
                          setDialogState: setDialogState,
                        ),
                      ] else ...[
                        imageUrlEditor(
                          label: 'URL immagine SaveIn',
                          helper:
                              'Immagine mostrata agli utenti SaveIn nella cross promo.',
                          controller: saveInImageUrlController,
                          uploadSuffix: 'savein',
                          setDialogState: setDialogState,
                        ),
                        const SizedBox(height: 12),
                        imageUrlEditor(
                          label: 'URL immagine SmartChef',
                          helper:
                              'Immagine mostrata agli utenti SmartChef nella cross promo.',
                          controller: smartChefImageUrlController,
                          uploadSuffix: 'smartchef',
                          setDialogState: setDialogState,
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: priorityController,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Priorita'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: startsAtController,
                              readOnly: true,
                              onTap: () => _pickPromotionDate(
                                controller: startsAtController,
                                dialogContext: dialogContext,
                                setDialogState: setDialogState,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Inizio validita',
                                hintText: 'gg/mm/aaaa',
                                suffixIcon: Icon(Icons.calendar_month_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: endsAtController,
                              readOnly: true,
                              onTap: () => _pickPromotionDate(
                                controller: endsAtController,
                                dialogContext: dialogContext,
                                setDialogState: setDialogState,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Fine validita',
                                hintText: 'gg/mm/aaaa',
                                suffixIcon: Icon(Icons.calendar_month_outlined),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: active,
                        title: const Text('Attivo'),
                        onChanged: (value) =>
                            setDialogState(() => active = value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: oncePerUser,
                        title: const Text('Una sola volta per utente'),
                        onChanged: (value) =>
                            setDialogState(() => oncePerUser = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annulla'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Salva'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!saved) return;
    final id = idController.text.trim();
    if (id.isEmpty) {
      _showAdminSnackBar('ID banner obbligatorio', isError: true);
      return;
    }
    final startsAt = _parseDateInput(startsAtController.text.trim());
    final endsAt =
        _parseDateInput(endsAtController.text.trim(), endOfDay: true);
    final targetApp = type == 'cross_promo' ? 'both' : 'savein';

    if (active) {
      await _deactivateOtherPromotionBanners(id);
    }
    await _firestore.collection('promotion_banners').doc(id).set({
      'active': active,
      'app': targetApp,
      'apps': targetApp == 'both' ? ['savein', 'smartchef'] : [targetApp],
      'type': type,
      'title': titleController.text.trim(),
      'message': messageController.text.trim(),
      'ctaLabel': isCrossPromoType() ? ctaController.text.trim() : '',
      'secondaryCtaLabel':
          isCrossPromoType() ? secondaryController.text.trim() : '',
      'action': isCrossPromoType() ? 'activate_cross_promo' : 'open_url',
      'actionUrl': urlController.text.trim(),
      'imageUrl': type == 'generic_promo' ? imageUrlController.text.trim() : '',
      'saveinImageUrl':
          type == 'cross_promo' ? saveInImageUrlController.text.trim() : '',
      'smartchefImageUrl':
          type == 'cross_promo' ? smartChefImageUrlController.text.trim() : '',
      'targetApp': targetApp,
      'direction': type == 'cross_promo' ? 'savein_to_smartchef' : '',
      'priority': int.tryParse(priorityController.text.trim()) ?? 10,
      'oncePerUser': oncePerUser,
      'startsAt': startsAt == null ? null : Timestamp.fromDate(startsAt),
      'endsAt': endsAt == null ? null : Timestamp.fromDate(endsAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': AuthService().currentUser?.email,
      if (existing == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> _pickAndUploadPromotionBannerImage({
    required String docId,
  }) async {
    try {
      final input = html.FileUploadInputElement()
        ..accept = 'image/png,image/jpeg,image/webp'
        ..multiple = false;
      input.click();
      await input.onChange.first;

      final file = input.files?.isNotEmpty == true ? input.files!.first : null;
      if (file == null) return null;

      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final result = reader.result;
      final Uint8List bytes;
      if (result is ByteBuffer) {
        bytes = Uint8List.view(result);
      } else if (result is Uint8List) {
        bytes = result;
      } else if (result is List<int>) {
        bytes = Uint8List.fromList(result);
      } else {
        throw Exception('Formato file non leggibile');
      }

      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('Immagine non valida');
      }
      if (decoded.width < 900 || decoded.height < 300) {
        _showAdminSnackBar(
          'Immagine caricata, ma consigliata almeno 1200x400 px',
        );
      }

      final safeDocId = docId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final safeFileName =
          file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final callable = FirebaseFunctions.instance.httpsCallable(
        'uploadPromotionBannerImage',
      );
      final response = await callable.call<Map<String, dynamic>>(
        {
          'docId': safeDocId,
          'fileName': safeFileName,
          'contentType': file.type.isEmpty ? 'image/png' : file.type,
          'base64': base64Encode(bytes),
          'width': decoded.width,
          'height': decoded.height,
        },
      );
      final data = Map<String, dynamic>.from(response.data);
      return data['imageUrl']?.toString();
    } catch (error) {
      _showAdminSnackBar(
        'Errore caricamento immagine: $error',
        isError: true,
      );
      return null;
    }
  }

  Future<String?> _showPromotionBannerImageHistory() async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Storico immagini banner'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: FutureBuilder<List<_PromotionBannerImageAsset>>(
            future: _loadPromotionBannerImageHistory(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final images =
                  snapshot.data ?? const <_PromotionBannerImageAsset>[];
              if (images.isEmpty) {
                return const Center(
                  child: Text('Nessuna immagine caricata nello storico.'),
                );
              }
              return GridView.builder(
                itemCount: images.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisExtent: 220,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (context, index) {
                  final image = images[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Image.network(
                            image.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            image.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => Navigator.of(dialogContext)
                                      .pop(image.imageUrl),
                                  child: const Text('Usa'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Elimina definitivamente',
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title:
                                              const Text('Eliminare immagine?'),
                                          content: const Text(
                                            'Il file verra eliminato definitivamente dallo Storage. Se un banner la usa ancora, non sara piu visibile.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(false),
                                              child: const Text('Annulla'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(true),
                                              child: const Text('Elimina'),
                                            ),
                                          ],
                                        ),
                                      ) ??
                                      false;
                                  if (!confirmed) return;
                                  await _deletePromotionBannerImage(
                                      image.filePath);
                                  if (!dialogContext.mounted) return;
                                  Navigator.of(dialogContext).pop();
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Future<List<_PromotionBannerImageAsset>>
      _loadPromotionBannerImageHistory() async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'listPromotionBannerImages',
    );
    final response = await callable.call<Map<String, dynamic>>();
    final data = Map<String, dynamic>.from(response.data);
    final rawImages = data['images'];
    if (rawImages is! List) return const [];
    return rawImages
        .whereType<Map>()
        .map((item) => _PromotionBannerImageAsset.fromMap(
              Map<String, dynamic>.from(item),
            ))
        .where((item) => item.imageUrl.isNotEmpty && item.filePath.isNotEmpty)
        .toList();
  }

  Future<void> _deletePromotionBannerImage(String filePath) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'deletePromotionBannerImage',
    );
    await callable.call<Map<String, dynamic>>({'filePath': filePath});
    _showAdminSnackBar('Immagine eliminata definitivamente');
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
              constraints: const BoxConstraints(maxWidth: 1400),
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
                      _StatCard(
                        label: 'Utenti SaveIn',
                        value: '${stats.totalUsers}',
                        color: Colors.green.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildFreePremiumStatsPanel(stats),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      final tags = _buildGlobalRankingPanel(
                        title: 'Top 20 tag più utilizzati',
                        subtitle:
                            'Tag più ricorrenti nei post salvati dagli utenti SaveIn.',
                        entries: stats.topTags,
                        emptyText: 'Nessun tag trovato.',
                      );
                      final folders = _buildGlobalRankingPanel(
                        title: 'Top 20 nomi cartelle più utilizzati',
                        subtitle:
                            'Nomi cartella più ripetuti tra tutti gli utenti.',
                        entries: stats.topFolderNames,
                        emptyText: 'Nessuna cartella trovata.',
                      );

                      if (!wide) {
                        return Column(
                          children: [
                            tags,
                            const SizedBox(height: 16),
                            folders,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: tags),
                          const SizedBox(width: 16),
                          Expanded(child: folders),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildGlobalRankingPanel(
                    title: 'Top 10 provenienze',
                    subtitle:
                        'Social, domini o siti da cui gli utenti salvano più post.',
                    entries: stats.topSources,
                    emptyText: 'Nessuna provenienza trovata.',
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

  Widget _buildFreePremiumStatsPanel(_GlobalContentStats stats) {
    final total = stats.totalUsers == 0 ? 1 : stats.totalUsers;
    String percent(int value) => '${(value / total * 100).toStringAsFixed(1)}%';

    Widget row({
      required String label,
      required int value,
      required Color color,
    }) {
      final ratio = stats.totalUsers == 0 ? 0.0 : value / stats.totalUsers;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$value (${percent(value)})',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      );
    }

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
            'Differenza utenti Free / Premium',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Distribuzione dei piani degli utenti SaveIn. Gli admin sono separati dai Premium.',
            style: TextStyle(color: Color(0xFF4B5563), fontSize: 13),
          ),
          const SizedBox(height: 14),
          row(
              label: 'Free',
              value: stats.freeUsers,
              color: Colors.blue.shade700),
          row(
            label: 'Premium',
            value: stats.premiumUsers,
            color: Colors.green.shade700,
          ),
          row(
            label: 'Admin',
            value: stats.adminUsers,
            color: Colors.orange.shade800,
          ),
        ],
      ),
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
              constraints: const BoxConstraints(maxWidth: 1400),
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

  Widget _buildUserSubNav() {
    if (_selectedUserId == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Sezione utente:',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          _UserSectionTab(
            label: 'Dettaglio',
            selected: _activeSection == _AdminDashboardSection.userDetail,
            onPressed: () {
              setState(() {
                _activeSection = _AdminDashboardSection.userDetail;
              });
            },
          ),
          _UserSectionTab(
            label: 'Post salvati',
            selected: _activeSection == _AdminDashboardSection.userPosts,
            onPressed: () {
              setState(() {
                _activeSection = _AdminDashboardSection.userPosts;
                _postsPage = 0;
                _postSourceFilter = null;
              });
            },
          ),
          _UserSectionTab(
            label: 'Cartelle',
            selected: _activeSection == _AdminDashboardSection.userFolders,
            onPressed: () {
              setState(() {
                _activeSection = _AdminDashboardSection.userFolders;
                _foldersPage = 0;
              });
            },
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
          constraints: const BoxConstraints(maxWidth: 1400),
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
                _buildUserSubNav(),
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
                      role: user.effectiveRole,
                      color: _roleColor(user.effectiveRole),
                      label: _roleLabel(user.effectiveRole),
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.workspace_premium_outlined),
                        label: Text(
                          'Scadenza Premium: ${_premiumExpiryLabel(user)}',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _updatingUserIds.contains(user.id) ||
                                !_canManageUserRoles
                            ? null
                            : () => _editUserPremiumExpiry(user),
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: const Text('Modifica scadenza'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _InfoRow(
                    label: 'Creato il', value: _formatDate(user.createdAt)),
                _InfoRow(
                  label: 'Fine Premium',
                  value: _premiumExpiryLabel(user),
                  valueColor: user.premiumUntil != null &&
                          user.premiumUntil!.isBefore(DateTime.now())
                      ? Colors.red.shade700
                      : null,
                ),
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
                _buildAccountHistoryPanel(user),
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
                  valueColor:
                      user.acceptedMarketing ? Colors.green : Colors.red,
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

  Widget _buildAccountHistoryPanel(_AdminUserRecord user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Storico account e piano',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Registrazione, passaggi Free/Premium/Admin, scadenze e cross-promo. Non viene cancellato quando si azzera lo storico test cross-promo.',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<_AccountHistoryEntry>>(
            future: _loadAccountHistoryEntries(user),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return Text(
                  'Errore caricamento storico: ${snapshot.error}',
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                );
              }
              final entries = snapshot.data ?? const <_AccountHistoryEntry>[];
              return Column(
                children: [
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Nessuno storico registrato. I prossimi eventi saranno salvati qui.',
                        style:
                            TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                      ),
                    ),
                  ...entries.map((entry) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(entry.icon, color: entry.color),
                      title: Text(
                        entry.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${_formatDate(entry.when)} • ${entry.source}\n${entry.detail}',
                      ),
                      isThreeLine: true,
                    );
                  }),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<_AccountHistoryEntry>> _loadAccountHistoryEntries(
    _AdminUserRecord user,
  ) async {
    final entries = <_AccountHistoryEntry>[];
    void add({
      required DateTime? when,
      required String title,
      required String source,
      required String detail,
      IconData icon = Icons.history,
      Color color = const Color(0xFF2563EB),
    }) {
      entries.add(_AccountHistoryEntry(
        when: when,
        title: title,
        source: source,
        detail: detail,
        icon: icon,
        color: color,
      ));
    }

    String statusLabel(dynamic value) {
      switch ((value ?? '').toString().trim().toLowerCase()) {
        case 'started':
          return 'prenotata';
        case 'pending':
          return 'in attesa';
        case 'claimed':
          return 'completata';
        case 'sent':
          return 'inviata';
        case 'premium':
          return 'Premium';
        case 'free':
          return 'Free';
        case 'admin':
          return 'Admin';
        default:
          final text = (value ?? '').toString().trim();
          return text.isEmpty ? '—' : text;
      }
    }

    String directionLabel(dynamic value) {
      switch ((value ?? '').toString().trim()) {
        case 'smartchef_to_savein':
          return 'da SmartChef verso SaveIn!';
        case 'savein_to_smartchef':
          return 'da SaveIn! verso SmartChef';
        default:
          final text = (value ?? '').toString().trim();
          return text.isEmpty ? '—' : text;
      }
    }

    Future<String> promotionLabel(String id) async {
      final promoId = id.trim();
      if (promoId.isEmpty) return 'Promo';
      if (promoId == 'smartchef_savein_launch') {
        return 'Cross-promo SmartChef ↔ SaveIn!';
      }
      try {
        final snap =
            await _firestore.collection('promotion_banners').doc(promoId).get();
        final data = snap.data() ?? <String, dynamic>{};
        final label = (data['title'] ?? data['name'] ?? data['message'] ?? '')
            .toString()
            .trim();
        return label.isEmpty ? promoId : label;
      } catch (_) {
        return promoId;
      }
    }

    if (user.createdAt != null) {
      add(
        when: user.createdAt,
        title: 'Registrazione account',
        source: 'auth/signup',
        detail: 'Account creato',
        icon: Icons.person_add_alt_1,
        color: const Color(0xFF15803D),
      );
    }

    final adminLogs = await _firestore
        .collection('admin_logs')
        .where('targetUserId', isEqualTo: user.id)
        .get();
    for (final doc in adminLogs.docs) {
      final data = doc.data();
      final action = (data['action'] ?? '').toString();
      final details = data['details'] is Map
          ? Map<String, dynamic>.from(data['details'] as Map)
          : <String, dynamic>{};
      if (action == 'role_changed') {
        final oldRole = details['oldRole'];
        final newRole = details['newRole'];
        final roleDetail = oldRole == null
            ? 'Nuovo piano: ${statusLabel(newRole)}'
            : '${statusLabel(oldRole)} → ${statusLabel(newRole)}';
        add(
          when: _parseDate(data['timestamp']),
          title: 'Cambio piano account',
          source: 'admin_logs',
          detail: roleDetail,
          icon: Icons.swap_horiz_outlined,
          color: const Color(0xFF2563EB),
        );
      } else if (action == 'premium_expiry_changed') {
        final premiumUntil = _parseDate(details['premiumUntil']);
        add(
          when: _parseDate(data['timestamp']),
          title: premiumUntil == null
              ? 'Scadenza Premium rimossa'
              : 'Scadenza Premium aggiornata',
          source: 'admin_logs',
          detail: premiumUntil == null
              ? 'Premium senza scadenza manuale'
              : 'Premium fino a ${_formatDate(premiumUntil)}',
          icon: Icons.workspace_premium_outlined,
          color: const Color(0xFF7C3AED),
        );
      }
    }

    final userSnap = await _firestore.collection('users').doc(user.id).get();
    final userData = userSnap.data() ?? <String, dynamic>{};
    final birthdayOffer = userData['birthdayOffer'];
    if (birthdayOffer is Map) {
      final offer = Map<String, dynamic>.from(birthdayOffer);
      add(
        when: _parseDate(offer['assignedAt']),
        title: 'Promo compleanno assegnata',
        source: 'birthday_offer',
        detail:
            '${offer['offerName'] ?? 'Offerta compleanno'}${(offer['promoCode'] ?? '').toString().isNotEmpty ? ' · Codice: ${offer['promoCode']}' : ''}',
        icon: Icons.cake_outlined,
        color: const Color(0xFFDB2777),
      );
    }

    try {
      final audit = await _firestore
          .collection('users')
          .doc(user.id)
          .collection('account_history')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      for (final doc in audit.docs) {
        final data = doc.data();
        final before = data['before'] is Map
            ? Map<String, dynamic>.from(data['before'] as Map)
            : <String, dynamic>{};
        final after = data['after'] is Map
            ? Map<String, dynamic>.from(data['after'] as Map)
            : <String, dynamic>{};
        final details = <String>[];
        final beforeRole = before['role']?.toString();
        final afterRole = after['role']?.toString();
        if ((beforeRole ?? '').isNotEmpty || (afterRole ?? '').isNotEmpty) {
          details.add('${beforeRole ?? '—'} → ${afterRole ?? '—'}');
        }
        final beforeUntil = _parseDate(before['premiumUntil']);
        final afterUntil = _parseDate(after['premiumUntil']);
        if (beforeUntil != null || afterUntil != null) {
          details.add(
            'Scadenza: ${_formatDate(beforeUntil)} → ${_formatDate(afterUntil)}',
          );
        }
        if (after['durationDays'] != null) {
          details.add('${after['durationDays']} giorni Premium');
        }
        add(
          when: _parseDate(data['createdAt']),
          title: (data['title'] as String?) ?? 'Evento account',
          source: (data['source'] as String?) ?? '',
          detail: details.isEmpty ? '—' : details.join(' · '),
        );
      }
    } catch (e) {
      add(
        when: null,
        title: 'Storico dettagliato non disponibile',
        source: 'account_history',
        detail:
            'Uso lo storico admin disponibile. Dettaglio non caricato: ${e.toString().replaceFirst('Exception: ', '')}',
        icon: Icons.info_outline,
        color: const Color(0xFFB45309),
      );
    }

    final redemptions = await _firestore
        .collection('promotion_redemptions')
        .where('userId', isEqualTo: user.id)
        .get();
    for (final doc in redemptions.docs) {
      final data = doc.data();
      final premiumUntil = _parseDate(data['premiumUntil']);
      final promoTitle =
          await promotionLabel((data['promotionId'] ?? '').toString());
      final parts = <String>[
        promoTitle,
        'Stato: ${statusLabel(data['status'] ?? 'riscattato')}',
        if ((data['direction'] ?? '').toString().isNotEmpty)
          'Direzione: ${directionLabel(data['direction'])}',
        if (premiumUntil != null) 'Premium fino a ${_formatDate(premiumUntil)}',
      ];
      add(
        when: _parseDate(data['redeemedAt']),
        title: 'Promo/banner utilizzato',
        source: 'promotion_redemptions',
        detail: parts.join(' · '),
        icon: Icons.local_offer_outlined,
        color: const Color(0xFF7C3AED),
      );
    }

    final firstClaims = await _firestore
        .collection('new_signup_premium_promo_claims')
        .where('firstUserId', isEqualTo: user.id)
        .get();
    final lastClaims = await _firestore
        .collection('new_signup_premium_promo_claims')
        .where('lastUserId', isEqualTo: user.id)
        .get();
    final claimDocs = {
      for (final doc in firstClaims.docs) doc.id: doc,
      for (final doc in lastClaims.docs) doc.id: doc,
    }.values;
    for (final doc in claimDocs) {
      final data = doc.data();
      final premiumUntil = _parseDate(data['premiumUntil']);
      final parts = <String>[
        '${data['durationDays'] ?? '—'} giorni Premium',
        if (premiumUntil != null) 'Premium fino a ${_formatDate(premiumUntil)}',
      ];
      add(
        when: _parseDate(data['startedAt']),
        title: 'Promo benvenuto riscattata',
        source: 'new_signup_promo',
        detail: parts.join(' · '),
        icon: Icons.card_giftcard_outlined,
        color: const Color(0xFFD97706),
      );
    }

    final crossSource = await _firestore
        .collection('cross_app_promos')
        .where('sourceUid', isEqualTo: user.id)
        .get();
    final crossSaveIn = await _firestore
        .collection('cross_app_promos')
        .where('saveinUid', isEqualTo: user.id)
        .get();
    final crossDocs = {
      for (final doc in crossSource.docs) doc.id: doc,
      for (final doc in crossSaveIn.docs) doc.id: doc,
    }.values;
    for (final doc in crossDocs) {
      final data = doc.data();
      final direction = (data['direction'] ?? '').toString().isNotEmpty
          ? data['direction']
          : '${data['sourceApp'] ?? '?'}_to_${data['targetApp'] ?? '?'}';
      add(
        when: _parseDate(data['saveinClaimedAt']) ??
            _parseDate(data['saveinStartedAt']) ??
            _parseDate(data['updatedAt']) ??
            _parseDate(data['createdAt']),
        title: 'Cross-promo',
        source: 'cross_app_promos',
        detail:
            'Direzione: ${directionLabel(direction)} · Stato: ${statusLabel(data['status'])} · ${data['durationDays'] ?? '—'} giorni Premium',
        icon: Icons.compare_arrows_outlined,
        color: const Color(0xFF0891B2),
      );
    }

    entries.sort((a, b) {
      final left = a.when ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.when ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return entries.take(100).toList();
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
          constraints: const BoxConstraints(maxWidth: 1400),
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
              _buildUserSubNav(),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
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
      ),
    );
  }
}

class _UserSectionTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _UserSectionTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      elevation: selected ? 1 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? const Color(0xFF6366F1) : const Color(0xFFD1D5DB),
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? const Color(0xFF4338CA) : const Color(0xFF374151),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
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
  planLimits,
  globalStats,
  finance,
  notifications,
  promos,
  accesses,
}

enum _NotificationMode { notification, email }

class _PromoDropdownHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PromoDropdownHeader({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.orange.shade800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoDropdownOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? inactiveLabel;

  const _PromoDropdownOption({
    required this.icon,
    required this.title,
    this.inactiveLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF667085)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (inactiveLabel != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Text(
              inactiveLabel!,
              style: const TextStyle(
                color: Color(0xFFC2410C),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PromotionBannerListRow extends StatelessWidget {
  final _PromotionBannerRecord banner;
  final Future<_PromotionBannerStats> Function(String id) loadStats;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  const _PromotionBannerListRow({
    required this.banner,
    required this.loadStats,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        banner.active ? const Color(0xFF166534) : const Color(0xFF6B7280);
    final activeBg =
        banner.active ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6);
    final title = banner.title.trim().isEmpty ? banner.id : banner.title.trim();
    final previewImageUrl = banner.previewImageUrl;
    final hasImage = previewImageUrl.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 190,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 3,
                  child: hasImage
                      ? Image.network(
                          previewImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFF3F4F6),
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        )
                      : Container(
                          color: const Color(0xFFF3F4F6),
                          alignment: Alignment.center,
                          child: const Text(
                            'Nessuna immagine',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: activeBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          banner.active ? 'ATTIVO' : 'SPENTO',
                          style: TextStyle(
                            color: activeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        'Priorita ${banner.priority}',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        banner.type,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'App: ${banner.app}',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    banner.message.trim().isEmpty ? banner.id : banner.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<_PromotionBannerStats>(
                    future: loadStats(banner.id),
                    builder: (context, snapshot) {
                      final stats = snapshot.data;
                      if (stats == null) {
                        return const Text(
                          'Statistiche in caricamento...',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                          ),
                        );
                      }
                      return Text(
                        'Viste ${stats.views} · Click ${stats.clicks} · Utilizzi ${stats.redemptions}',
                        style: const TextStyle(
                          color: Color(0xFF374151),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => onToggle(!banner.active),
                    icon: Icon(
                      banner.active ? Icons.pause_circle : Icons.play_arrow,
                      size: 16,
                    ),
                    label: Text(banner.active ? 'Disattiva' : 'Attiva'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Modifica'),
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

class _PromotionSetupCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PromotionSetupCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.add_circle_outline, color: Color(0xFF6D28D9)),
          ],
        ),
      ),
    );
  }
}

class _PromotionBannerHistoryTile extends StatelessWidget {
  final _PromotionBannerRecord banner;
  final Future<_PromotionBannerStats> Function(String id) loadStats;
  final VoidCallback onReactivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PromotionBannerHistoryTile({
    required this.banner,
    required this.loadStats,
    required this.onReactivate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = banner.title.trim().isEmpty ? banner.id : banner.title.trim();
    final previewImageUrl = banner.previewImageUrl;
    final hasImage = previewImageUrl.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 3,
              child: hasImage
                  ? Image.network(
                      previewImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFF3F4F6),
                        alignment: Alignment.center,
                        child:
                            const Icon(Icons.broken_image_outlined, size: 18),
                      ),
                    )
                  : Container(
                      color: const Color(0xFFF3F4F6),
                      alignment: Alignment.center,
                      child: const Text(
                        'No img',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _PromotionDateBadge(
                    label: 'INIZIO',
                    value: _formatDateOnly(banner.startsAt ?? banner.createdAt),
                  ),
                  _PromotionDateBadge(
                    label: 'FINE',
                    value: _formatDateOnly(banner.endsAt),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${banner.active ? 'attiva ma scaduta' : 'spenta'} · ${banner.type}',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        trailing: FutureBuilder<_PromotionBannerStats>(
          future: loadStats(banner.id),
          builder: (context, snapshot) {
            final stats = snapshot.data;
            if (stats == null) {
              return const SizedBox(
                width: 88,
                child: LinearProgressIndicator(minHeight: 3),
              );
            }
            return SizedBox(
              width: 190,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onReactivate,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Riattiva'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${stats.clicks} click · CTR ${_formatCtr(stats)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        children: [
          FutureBuilder<_PromotionBannerStats>(
            future: loadStats(banner.id),
            builder: (context, snapshot) {
              final stats = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _PromotionMetricChip(
                        label: 'Viste',
                        value: stats == null ? '...' : stats.views.toString(),
                      ),
                      _PromotionMetricChip(
                        label: 'Click',
                        value: stats == null ? '...' : stats.clicks.toString(),
                      ),
                      _PromotionMetricChip(
                        label: 'CTR',
                        value: stats == null ? '...' : _formatCtr(stats),
                      ),
                      _PromotionMetricChip(
                        label: 'Utilizzi',
                        value: stats == null
                            ? '...'
                            : stats.redemptions.toString(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _PromotionDetailLine(label: 'ID', value: banner.id),
                  _PromotionDetailLine(
                      label: 'Periodo', value: _formatPeriod(banner)),
                  _PromotionDetailLine(label: 'App', value: banner.app),
                  _PromotionDetailLine(label: 'Tipo', value: banner.type),
                  _PromotionDetailLine(
                    label: 'Priorita',
                    value: banner.priority.toString(),
                  ),
                  _PromotionDetailLine(
                    label: 'Una volta per utente',
                    value: banner.oncePerUser ? 'Si' : 'No',
                  ),
                  _PromotionDetailLine(
                    label: 'URL azione',
                    value: banner.actionUrl.trim().isEmpty
                        ? '-'
                        : banner.actionUrl,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    banner.message.trim().isEmpty ? '-' : banner.message,
                    style: const TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Riapri / modifica'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Elimina dal DB'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatPeriod(_PromotionBannerRecord banner) {
    final start = _formatDateOnly(banner.startsAt ?? banner.createdAt);
    final end = _formatDateOnly(banner.endsAt);
    if (start == '-' && end == '-') return 'Periodo non impostato';
    if (end == '-') return 'Dal $start';
    if (start == '-') return 'Fino al $end';
    return '$start - $end';
  }

  static String _formatDateOnly(DateTime? date) {
    if (date == null) return '-';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  static String _formatCtr(_PromotionBannerStats stats) {
    if (stats.views <= 0) return '0%';
    final value = (stats.clicks / stats.views) * 100;
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}%';
  }
}

class _PromotionDateBadge extends StatelessWidget {
  final String label;
  final String value;

  const _PromotionDateBadge({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFB923C), width: 1.2),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: Color(0xFF9A3412),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(color: Color(0xFF111827)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromotionMetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _PromotionMetricChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromotionDetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _PromotionDetailLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromotionBannerRecord {
  final String id;
  final bool active;
  final String app;
  final String type;
  final String title;
  final String message;
  final String ctaLabel;
  final String secondaryCtaLabel;
  final String actionUrl;
  final String imageUrl;
  final String saveinImageUrl;
  final String smartchefImageUrl;
  final int priority;
  final bool oncePerUser;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const _PromotionBannerRecord({
    required this.id,
    required this.active,
    required this.app,
    required this.type,
    required this.title,
    required this.message,
    required this.ctaLabel,
    required this.secondaryCtaLabel,
    required this.actionUrl,
    required this.imageUrl,
    required this.saveinImageUrl,
    required this.smartchefImageUrl,
    required this.priority,
    required this.oncePerUser,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.updatedAt,
  });

  String get previewImageUrl {
    if (app == 'smartchef' && smartchefImageUrl.trim().isNotEmpty) {
      return smartchefImageUrl.trim();
    }
    if (saveinImageUrl.trim().isNotEmpty) return saveinImageUrl.trim();
    if (smartchefImageUrl.trim().isNotEmpty) return smartchefImageUrl.trim();
    return imageUrl.trim();
  }

  factory _PromotionBannerRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return _PromotionBannerRecord(
      id: doc.id,
      active: data['active'] == true,
      app: (data['app'] ?? data['targetApp'] ?? 'savein').toString(),
      type: (data['type'] ?? 'generic_promo').toString(),
      title: (data['title'] ?? '').toString(),
      message: (data['message'] ?? '').toString(),
      ctaLabel: (data['ctaLabel'] ?? '').toString(),
      secondaryCtaLabel: (data['secondaryCtaLabel'] ?? '').toString(),
      actionUrl: (data['actionUrl'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      saveinImageUrl: (data['saveinImageUrl'] ?? '').toString(),
      smartchefImageUrl: (data['smartchefImageUrl'] ?? '').toString(),
      priority: (data['priority'] as num?)?.toInt() ?? 0,
      oncePerUser: data['oncePerUser'] != false,
      startsAt: parseDate(data['startsAt']),
      endsAt: parseDate(data['endsAt']),
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
    );
  }
}

class _PromotionBannerStats {
  final int views;
  final int clicks;
  final int redemptions;

  const _PromotionBannerStats({
    required this.views,
    required this.clicks,
    required this.redemptions,
  });
}

class _PromotionBannerImageAsset {
  final String filePath;
  final String imageUrl;
  final String fileName;

  const _PromotionBannerImageAsset({
    required this.filePath,
    required this.imageUrl,
    required this.fileName,
  });

  factory _PromotionBannerImageAsset.fromMap(Map<String, dynamic> data) {
    return _PromotionBannerImageAsset(
      filePath: (data['filePath'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      fileName: (data['fileName'] ?? '').toString(),
    );
  }
}

class _AdminInfoBox extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _AdminInfoBox({
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $line'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminEmptyState extends StatelessWidget {
  final String message;

  const _AdminEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
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
  final int totalUsers;
  final int freeUsers;
  final int premiumUsers;
  final int adminUsers;
  final List<MapEntry<String, int>> topSources;
  final List<MapEntry<String, int>> topCreators;
  final List<MapEntry<String, int>> topTags;
  final List<MapEntry<String, int>> topFolderNames;

  const _GlobalContentStats({
    required this.totalPosts,
    required this.totalFolders,
    required this.totalUsers,
    required this.freeUsers,
    required this.premiumUsers,
    required this.adminUsers,
    required this.topSources,
    required this.topCreators,
    required this.topTags,
    required this.topFolderNames,
  });

  const _GlobalContentStats.empty()
      : totalPosts = 0,
        totalFolders = 0,
        totalUsers = 0,
        freeUsers = 0,
        premiumUsers = 0,
        adminUsers = 0,
        topSources = const [],
        topCreators = const [],
        topTags = const [],
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
  final DateTime? premiumUntil;
  final DateTime? birthDate;
  final String? gender;
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
    required this.premiumUntil,
    this.birthDate,
    this.gender,
    required this.acceptedMarketing,
    this.marketingConsentDate,
  });

  factory _AdminUserRecord.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    // Filtro per app_id: escludiamo utenti SmartChef se presente un app_id diverso da 'savein'
    // Se app_id è null, assumiamo sia SaveIn (vecchi utenti)
    final appId = data['app_id'] as String?;
    if (appId != null && appId != 'savein') {
      // Restituiamo un record "vuoto" o marcato, che verrà filtrato dopo
      return _AdminUserRecord.empty(doc.id);
    }

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
      premiumUntil: parseDate(data['premiumUntil']),
      birthDate: parseDate(data['birthDate']),
      gender: data['gender'] as String?,
      acceptedMarketing: marketing?['accepted'] ?? false,
      marketingConsentDate: parseDate(marketing?['lastModified']) ??
          parseDate(marketing?['consentDate']),
    );
  }

  DashboardAccessRole get effectiveDashboardRole =>
      role == AppUserRole.admin ? DashboardAccessRole.admin : dashboardRole;

  // Rispecchia User.effectiveRole lato app: un utente con role='premium' ma
  // premiumUntil scaduto deve risultare Free anche in dashboard, altrimenti
  // il badge mostra "Premium" mentre la colonna scadenza lo segnala in rosso
  // come scaduto, generando una UI contraddittoria.
  AppUserRole get effectiveRole {
    if (role == AppUserRole.admin) return AppUserRole.admin;
    if (role == AppUserRole.premium && _isPremiumExpiryActive(premiumUntil)) {
      return AppUserRole.premium;
    }
    return AppUserRole.free;
  }

  static bool _isPremiumExpiryActive(DateTime? until) {
    if (until == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay = DateTime(until.year, until.month, until.day);
    return !today.isAfter(expiryDay);
  }

  bool get isPlaceholder => email == 'placeholder';

  factory _AdminUserRecord.empty(String id) {
    return _AdminUserRecord(
      id: id,
      name: '',
      email: 'placeholder',
      username: null,
      role: AppUserRole.free,
      dashboardRole: DashboardAccessRole.none,
      isBlocked: false,
      blockedReason: null,
      blockedAt: null,
      createdAt: null,
      lastLogin: null,
      premiumUntil: null,
      acceptedMarketing: false,
    );
  }
}

class _AccountHistoryEntry {
  final DateTime? when;
  final String title;
  final String source;
  final String detail;
  final IconData icon;
  final Color color;

  const _AccountHistoryEntry({
    required this.when,
    required this.title,
    required this.source,
    required this.detail,
    required this.icon,
    required this.color,
  });
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
      case 'premium_expiry_changed':
        return 'Scadenza Premium aggiornata';
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
    final premiumUntil = details['premiumUntil'];

    if (newRole != null) {
      return 'Target: $targetUserId • Nuovo ruolo: $newRole';
    }
    if (premiumUntil != null) {
      return 'Target: $targetUserId • Scadenza: $premiumUntil';
    }
    if (reason != null && reason.toString().trim().isNotEmpty) {
      return 'Target: $targetUserId • Motivo: $reason';
    }
    return 'Target: $targetUserId';
  }
}
