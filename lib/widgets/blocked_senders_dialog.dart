import 'package:flutter/material.dart';
import 'package:savein/data_service.dart';

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

class _BlockedSendersDialogState extends State<BlockedSendersDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _blocked = const [];

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
      final blocked = await DataService.instance.getBlockedSenders();
      if (!mounted) return;
      setState(() {
        _blocked = blocked;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossibile caricare gli utenti bloccati.';
        _loading = false;
      });
    }
  }

  Future<void> _unblock(Map<String, dynamic> item) async {
    final senderId =
        item['senderId']?.toString() ?? item['id']?.toString() ?? '';
    if (senderId.isEmpty) return;
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
    }
  }

  String _title(Map<String, dynamic> item) {
    final name = item['senderName']?.toString().trim() ?? '';
    final email = item['senderEmail']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return item['senderId']?.toString() ?? 'Utente';
  }

  String? _subtitle(Map<String, dynamic> item) {
    final name = item['senderName']?.toString().trim() ?? '';
    final email = item['senderEmail']?.toString().trim() ?? '';
    if (name.isNotEmpty && email.isNotEmpty) return email;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Utenti bloccati'),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text(_error!)
                : _blocked.isEmpty
                    ? const Text('Nessun utente bloccato.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _blocked.length,
                        itemBuilder: (context, index) {
                          final item = _blocked[index];
                          final subtitle = _subtitle(item);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(_title(item)),
                            subtitle: subtitle == null ? null : Text(subtitle),
                            trailing: TextButton(
                              onPressed: () => _unblock(item),
                              child: const Text('Sblocca'),
                            ),
                          );
                        },
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
