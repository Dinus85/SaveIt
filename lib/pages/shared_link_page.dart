import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/access_control_service.dart';
import '../services/share_link_service.dart';
import '../utils/theme_helpers.dart';

class SharedLinkPage extends StatefulWidget {
  final String token;
  final bool isDarkTheme;

  const SharedLinkPage({
    super.key,
    required this.token,
    required this.isDarkTheme,
  });

  @override
  State<SharedLinkPage> createState() => _SharedLinkPageState();
}

class _SharedLinkPageState extends State<SharedLinkPage> {
  SaveInShareLink? _link;
  bool _loading = true;
  bool _working = false;
  String? _error;

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
      final link = await ShareLinkService.instance.fetchShareLink(widget.token);
      if (mounted) {
        setState(() {
          _link = link;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Questo link non è più disponibile o non è valido.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _runImport() async {
    final link = _link;
    if (link == null) return;
    if (!AuthService().isLoggedIn) {
      _showMessage('Accedi o registrati per importare questo contenuto.');
      return;
    }
    setState(() => _working = true);
    try {
      // Controllo limiti dinamici
      if (mounted) {
        final canImport = await AppAccessService().checkFeatureAvailable(
          context,
          'import_shared',
          'Importazione Contenuti',
        );
        if (!canImport) return;
      }

      if (link.isFolder) {
        await ShareLinkService.instance.importFolder(link);
      } else {
        await ShareLinkService.instance.importPost(link);
      }
      if (!mounted) return;
      _showMessage(link.isFolder
          ? 'Cartella importata nella tua raccolta.'
          : 'Contenuto salvato nella tua raccolta.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        _showMessage('Errore durante l’importazione: $e');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openOriginal() async {
    final link = _link;
    if (link == null) return;
    await ShareLinkService.instance.openOriginalPost(link);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    return Scaffold(
      backgroundColor: colors.mainBackgroundColor,
      appBar: AppBar(
        backgroundColor: colors.mainBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.iconColor),
        title: Text(
          'Condivisione SaveIn',
          style:
              TextStyle(color: colors.titleColor, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.iconColor))
          : _error != null
              ? _buildError(colors)
              : _buildContent(colors),
    );
  }

  Widget _buildError(ThemeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _error!,
          style: TextStyle(color: colors.textColor, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildContent(ThemeColors colors) {
    final link = _link!;
    final imageUrl =
        (link.payload['previewStorageUrl'] as String?)?.trim().isNotEmpty ==
                true
            ? link.payload['previewStorageUrl'] as String
            : link.payload['imageUrl'] as String?;
    final postCount = (link.payload['posts'] as List?)?.length ?? 0;
    final folderCount = (link.payload['folders'] as List?)?.length ?? 0;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null && imageUrl.trim().isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    imageUrl,
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Icon(
                    link.isFolder ? Icons.folder_copy : Icons.article_outlined,
                    color: link.isFolder ? Colors.amber.shade700 : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    link.isFolder
                        ? 'Cartella condivisa'
                        : 'Contenuto condiviso',
                    style: TextStyle(
                      color: colors.subtitleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                link.title,
                style: TextStyle(
                  color: colors.titleColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Condiviso da ${link.ownerName}',
                style: TextStyle(color: colors.subtitleColor),
              ),
              if (link.isFolder) ...[
                const SizedBox(height: 8),
                Text(
                  '$folderCount cartelle e $postCount contenuti pronti da importare.',
                  style: TextStyle(color: colors.textColor),
                ),
              ],
              const SizedBox(height: 22),
              if (link.isPost)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _working ? null : _openOriginal,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Apri contenuto'),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _working ? null : _runImport,
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(link.isFolder
                          ? Icons.drive_folder_upload
                          : Icons.bookmark_add),
                  label: Text(
                      link.isFolder ? 'Importa cartella' : 'Salva in SaveIn'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
