import 'package:flutter/material.dart';
import 'package:savein/data_service.dart';
import 'package:savein/services/auth_service.dart';

class BlockedSendersDialog extends StatefulWidget {
  const BlockedSendersDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const BlockedSendersDialog(),
    );
  }

  @override
  State<BlockedSendersDialog> createState() => _BlockedSendersDialogState();
}

class _KnownShareUser {
  final String id;
  final String email;
  final String name;

  const _KnownShareUser({
    required this.id,
    required this.email,
    required this.name,
  });
}

class _BlockedSendersDialogState extends State<BlockedSendersDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _blocked = const [];
  List<_KnownShareUser> _known = const [];
  final Set<String> _busyIds = <String>{};
  final Set<String> _busyEmails = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DataService.instance.getBlockedSenders(),
        DataService.instance.getSharedContacts(),
        DataService.instance.getSharedItems(),
      ]);
      if (!mounted) return;

      final blocked = results[0] as List<Map<String, dynamic>>;
      final contacts = results[1] as List<String>;
      final sharedItems = results[2] as List<Map<String, dynamic>>;
      final me = AuthService().currentUser;
      final myId = me?.id ?? '';
      final myEmail = (me?.email ?? '').trim().toLowerCase();

      final blockedIds = <String>{};
      final blockedEmails = <String>{};
      for (final item in blocked) {
        final id = (item['senderId'] ?? item['id'] ?? '').toString().trim();
        final email =
            (item['senderEmail'] ?? '').toString().trim().toLowerCase();
        if (id.isNotEmpty) blockedIds.add(id);
        if (email.isNotEmpty) blockedEmails.add(email);
      }

      final known = <_KnownShareUser>[];
      final seenIds = <String>{};
      final seenEmails = <String>{};

      void addKnown({
        required String id,
        required String email,
        required String name,
      }) {
        final normalizedEmail = email.trim().toLowerCase();
        if (id.isNotEmpty && (id == myId || seenIds.contains(id))) return;
        if (normalizedEmail.isNotEmpty &&
            (normalizedEmail == myEmail ||
                seenEmails.contains(normalizedEmail))) {
          return;
        }
        if (id.isNotEmpty && blockedIds.contains(id)) return;
        if (normalizedEmail.isNotEmpty &&
            blockedEmails.contains(normalizedEmail)) {
          return;
        }
        if (id.isEmpty && normalizedEmail.isEmpty) return;
        if (id.isNotEmpty) seenIds.add(id);
        if (normalizedEmail.isNotEmpty) seenEmails.add(normalizedEmail);
        known.add(_KnownShareUser(
          id: id,
          email: normalizedEmail,
          name: name.trim(),
        ));
      }

      for (final item in sharedItems) {
        addKnown(
          id: item['ownerId']?.toString() ?? '',
          email: item['ownerEmail']?.toString() ?? '',
          name: item['ownerName']?.toString() ?? '',
        );
      }
      for (final email in contacts) {
        addKnown(id: '', email: email, name: '');
      }

      setState(() {
        _blocked = blocked;
        _known = known;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossibile caricare gli utenti.';
        _loading = false;
      });
    }
  }

  Future<void> _unblock(Map<String, dynamic> item) async {
    final senderId =
        item['senderId']?.toString() ?? item['id']?.toString() ?? '';
    if (senderId.isEmpty) return;
    setState(() => _busyIds.add(senderId));
    try {
      await DataService.instance.unblockShareSender(senderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utente sbloccato.')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile sbloccare questo utente.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(senderId));
      }
    }
  }

  Future<void> _blockKnown(_KnownShareUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Blocca utente'),
        content: Text(
          user.email.isNotEmpty
              ? 'Vuoi bloccare ${user.name.isNotEmpty ? user.name : user.email} (${user.email})? Non potrà più inviarti post o cartelle. Potrai sbloccarlo da questa pagina.'
              : 'Vuoi bloccare questo utente? Non potrà più inviarti post o cartelle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Blocca utente',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final busyKey = user.id.isNotEmpty ? user.id : user.email;
    setState(() {
      if (user.id.isNotEmpty) {
        _busyIds.add(user.id);
      } else {
        _busyEmails.add(user.email);
      }
    });

    try {
      var senderId = user.id;
      var senderEmail = user.email;
      var senderName = user.name;
      if (senderId.isEmpty) {
        final found = await DataService.instance.findUserByEmail(user.email);
        senderId = found?['id']?.toString() ?? '';
        senderEmail = found?['email']?.toString() ?? user.email;
        senderName = found?['name']?.toString() ?? user.name;
      }
      if (senderId.isEmpty) {
        throw Exception('Utente non trovato');
      }
      await DataService.instance.blockShareSender(
        senderId: senderId,
        senderEmail: senderEmail,
        senderName: senderName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utente bloccato.')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile bloccare questo utente.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyIds.remove(busyKey);
          _busyEmails.remove(busyKey);
        });
      }
    }
  }

  String _blockedTitle(Map<String, dynamic> item) {
    final name = item['senderName']?.toString().trim() ?? '';
    final email = item['senderEmail']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return item['senderId']?.toString() ?? 'Utente';
  }

  String? _blockedSubtitle(Map<String, dynamic> item) {
    final name = item['senderName']?.toString().trim() ?? '';
    final email = item['senderEmail']?.toString().trim() ?? '';
    if (name.isNotEmpty && email.isNotEmpty) return email;
    return null;
  }

  Widget _sectionTitle(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.7), width: 1.3),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Utenti e blocchi'),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text(_error!)
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 460),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        _sectionTitle('Utenti bloccati'),
                        if (_blocked.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text('Nessun utente bloccato.'),
                          )
                        else
                          ..._blocked.map((item) {
                            final subtitle = _blockedSubtitle(item);
                            final senderId = item['senderId']?.toString() ??
                                item['id']?.toString() ??
                                '';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(_blockedTitle(item)),
                              subtitle:
                                  subtitle == null ? null : Text(subtitle),
                              trailing: _actionButton(
                                label: 'Sblocca',
                                color: Colors.blue.shade700,
                                onPressed: _busyIds.contains(senderId)
                                    ? null
                                    : () => _unblock(item),
                              ),
                            );
                          }),
                        const Divider(height: 24),
                        _sectionTitle('Utenti conosciuti'),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Chi ti ha inviato contenuti o a cui hai già condiviso.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        if (_known.isEmpty)
                          const Text('Nessun utente conosciuto.')
                        else
                          ..._known.map((user) {
                            final title = user.name.isNotEmpty
                                ? user.name
                                : (user.email.isNotEmpty
                                    ? user.email
                                    : 'Utente');
                            final subtitle = user.name.isNotEmpty &&
                                    user.email.isNotEmpty
                                ? user.email
                                : null;
                            final busy = (user.id.isNotEmpty &&
                                    _busyIds.contains(user.id)) ||
                                (user.email.isNotEmpty &&
                                    _busyEmails.contains(user.email));
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(title),
                              subtitle:
                                  subtitle == null ? null : Text(subtitle),
                              trailing: _actionButton(
                                label: 'Blocca',
                                color: Colors.orange.shade700,
                                onPressed:
                                    busy ? null : () => _blockKnown(user),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}
