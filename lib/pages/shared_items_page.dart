import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:savein/data_service.dart';
import 'package:savein/models.dart';
import 'package:savein/models/folder.dart' show MockFolder;
import 'package:savein/pages/folder_detail_page.dart';
import 'package:savein/services/folder_service.dart';
import 'package:savein/utils/theme_helpers.dart';

class SharedItemsPage extends StatefulWidget {
  final bool isDarkTheme;
  static final Set<String> _importsInProgress = <String>{};

  const SharedItemsPage({
    Key? key,
    required this.isDarkTheme,
  }) : super(key: key);

  static Future<bool> showPendingSharedItemsPrompt(
    BuildContext context, {
    required bool isDarkTheme,
  }) async {
    try {
      final items = await DataService.instance.getSharedItems();
      final pendingItems = items
          .where((item) =>
              !_importsInProgress.contains(item['id']?.toString() ?? ''))
          .toList();
      if (!context.mounted || pendingItems.isEmpty) return false;
      return await _showImportPrompt(
            context,
            item: pendingItems.first,
            isDarkTheme: isDarkTheme,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  State<SharedItemsPage> createState() => _SharedItemsPageState();
}

class _SharedItemsPageState extends State<SharedItemsPage> {
  List<Map<String, dynamic>> _sharedItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSharedItems();
  }

  Future<void> _loadSharedItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await DataService.instance.getSharedItems();
      if (!mounted) return;
      setState(() {
        _sharedItems = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);

    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Condivisi con me',
          style: TextStyle(
            color: themeColors.titleColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: themeColors.mainBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: themeColors.iconColor),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sharedItems.isEmpty
              ? _buildEmptyState(themeColors)
              : RefreshIndicator(
                  onRefresh: _loadSharedItems,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sharedItems.length,
                    itemBuilder: (context, index) {
                      final item = _sharedItems[index];
                      return _buildSharedItemCard(item, themeColors);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState(ThemeColors themeColors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.share_outlined,
              size: 64,
              color: themeColors.subtitleColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Nessun elemento condiviso',
              style: TextStyle(
                color: themeColors.titleColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Gli elementi condivisi dagli altri utenti appariranno qui.',
              style: TextStyle(color: themeColors.subtitleColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadSharedItems,
              child: const Text('Aggiorna'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSharedItemCard(
    Map<String, dynamic> item,
    ThemeColors themeColors,
  ) {
    final type = item['type']?.toString() ?? 'post';
    final ownerName = item['ownerName']?.toString() ?? 'un utente';
    final originalData = _originalData(item);
    final title = _sharedItemTitle(item);
    final color = type == 'folder'
        ? _parseColor(originalData['color'])
        : const Color(0xFF2563EB);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            type == 'post' ? Icons.article : Icons.folder,
            color: color,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: themeColors.textColor,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Condiviso da $ownerName',
          style: TextStyle(color: themeColors.subtitleColor, fontSize: 12),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: () => _acceptItem(item),
              tooltip: 'Importa',
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => _rejectItem(item),
              tooltip: 'Rifiuta',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptItem(Map<String, dynamic> item) async {
    final imported = await _showImportPrompt(
      context,
      item: item,
      isDarkTheme: widget.isDarkTheme,
    );
    if (imported == true) {
      await _loadSharedItems();
    }
  }

  Future<void> _rejectItem(Map<String, dynamic> item) async {
    final rejected = await _rejectSharedItem(context, item);
    if (rejected && mounted) {
      await _loadSharedItems();
    }
  }

  Color _parseColor(dynamic colorData) {
    if (colorData is String) {
      try {
        return Color(int.parse(colorData.replaceAll('#', '0xFF')));
      } catch (_) {
        return const Color(0xFF2563EB);
      }
    }
    if (colorData is int) return Color(colorData);
    return const Color(0xFF2563EB);
  }
}

Map<String, dynamic> _originalData(Map<String, dynamic> item) {
  final data = item['originalData'];
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return <String, dynamic>{};
}

Map<String, dynamic> _mergeSharedPreviewData(
  Map<String, dynamic> item,
  Map<String, dynamic>? preview,
) {
  final base = Map<String, dynamic>.from(_originalData(item));
  if (preview == null || preview.isEmpty) return base;

  final folders = preview['folders'];
  final posts = preview['posts'];
  if (folders is List) {
    base['folders'] = folders
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
  if (posts is List) {
    base['posts'] = posts
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
  if (preview['folderCount'] != null) {
    base['folderCount'] = preview['folderCount'];
  }
  if (preview['postCount'] != null) {
    base['postCount'] = preview['postCount'];
  }
  if (preview['name'] != null) base['name'] = preview['name'];
  if (preview['title'] != null) base['title'] = preview['title'];
  if (preview['description'] != null) {
    base['description'] = preview['description'];
  }
  if (preview['imageUrl'] != null) base['imageUrl'] = preview['imageUrl'];
  if (preview['previewStorageUrl'] != null) {
    base['previewStorageUrl'] = preview['previewStorageUrl'];
  }
  if (preview['color'] != null) base['color'] = preview['color'];
  return base;
}

int _sharedPreviewFolderCount(Map<String, dynamic> originalData) {
  final explicit = originalData['folderCount'];
  if (explicit is int) return explicit;
  if (explicit != null) {
    return int.tryParse(explicit.toString()) ?? 0;
  }
  final folders = originalData['folders'] is List
      ? List<Map<String, dynamic>>.from(originalData['folders'])
      : <Map<String, dynamic>>[];
  return folders.length;
}

int _sharedPreviewPostCount(Map<String, dynamic> originalData) {
  final explicit = originalData['postCount'];
  if (explicit is int) return explicit;
  if (explicit != null) {
    return int.tryParse(explicit.toString()) ?? 0;
  }
  final posts = originalData['posts'] is List
      ? List<Map<String, dynamic>>.from(originalData['posts'])
      : <Map<String, dynamic>>[];
  return posts.length;
}

String _sharedItemTitle(Map<String, dynamic> item) {
  final type = item['type']?.toString() ?? 'post';
  final originalData = _originalData(item);
  return (type == 'post' ? originalData['title'] : originalData['name'])
              ?.toString()
              .trim()
              .isNotEmpty ==
          true
      ? (type == 'post' ? originalData['title'] : originalData['name'])
          .toString()
      : 'Senza titolo';
}

Widget _buildSharedItemPreview(
  Map<String, dynamic> originalData, {
  required String title,
  required bool isFolder,
  required bool isDarkTheme,
}) {
  final backgroundColor =
      isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade50;
  final borderColor = isDarkTheme ? Colors.white12 : Colors.black12;
  final textColor = isDarkTheme ? Colors.white : Colors.black87;
  final subtitleColor = isDarkTheme ? Colors.white70 : Colors.black54;

  if (!isFolder) {
    final imageUrl =
        (originalData['previewStorageUrl'] ?? originalData['imageUrl'])
            ?.toString()
            .trim();
    final description = originalData['description']?.toString().trim() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 88,
            height: 88,
            color: isDarkTheme ? Colors.grey.shade700 : Colors.grey.shade200,
            child: imageUrl != null && imageUrl.isNotEmpty
                ? _buildSharedRemotePreviewImage(
                    previewStorageUrl:
                        originalData['previewStorageUrl']?.toString(),
                    imageUrl: originalData['imageUrl']?.toString(),
                    fallbackIcon: Icons.article,
                  )
                : const Icon(Icons.article, size: 36),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subtitleColor, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  final folders = originalData['folders'] is List
      ? List<Map<String, dynamic>>.from(originalData['folders'])
      : <Map<String, dynamic>>[];
  final posts = originalData['posts'] is List
      ? List<Map<String, dynamic>>.from(originalData['posts'])
      : <Map<String, dynamic>>[];
  final folderCount = _sharedPreviewFolderCount(originalData);
  final postCount = _sharedPreviewPostCount(originalData);

  return AspectRatio(
    aspectRatio: 1.45,
    child: Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildSharedFolderPreviewGrid(posts, isDarkTheme),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.72),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.folder, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$folderCount cartell${folderCount == 1 ? 'a' : 'e'} incluse • $postCount post',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.86),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildSharedRemotePreviewImage({
  required String? previewStorageUrl,
  required String? imageUrl,
  required IconData fallbackIcon,
}) {
  final remoteUrl = previewStorageUrl?.trim();
  final originalUrl = imageUrl?.trim();
  final url = remoteUrl?.isNotEmpty == true ? remoteUrl! : originalUrl;

  if (url == null || url.isEmpty) {
    return Icon(fallbackIcon, size: 36, color: Colors.grey.shade500);
  }

  return CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    placeholder: (context, _) => Container(
      color: Colors.grey.shade200,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade400),
          ),
        ),
      ),
    ),
    errorWidget: (context, _, __) => Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.grey.shade400,
          size: 24,
        ),
      ),
    ),
  );
}

Widget _buildSharedFolderPreviewGrid(
  List<Map<String, dynamic>> posts,
  bool isDarkTheme,
) {
  final postsWithImages = posts
      .where((post) =>
          (post['previewStorageUrl'] ?? post['imageUrl'])
              ?.toString()
              .trim()
              .isNotEmpty ==
          true)
      .take(4)
      .toList();

  if (postsWithImages.isEmpty) {
    return Container(
      color: isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade200,
      child: CustomPaint(
        painter: _SharedFolderPatternPainter(isDarkTheme: isDarkTheme),
        child: Center(
          child: Icon(
            Icons.folder_open,
            size: 52,
            color: isDarkTheme ? Colors.white24 : Colors.black26,
          ),
        ),
      ),
    );
  }

  Widget tile(Map<String, dynamic> post) {
    return _buildSharedRemotePreviewImage(
      previewStorageUrl: post['previewStorageUrl']?.toString(),
      imageUrl: post['imageUrl']?.toString(),
      fallbackIcon: Icons.article,
    );
  }

  if (postsWithImages.length == 1) return tile(postsWithImages.first);
  if (postsWithImages.length == 2) {
    return Row(
      children: [
        Expanded(child: tile(postsWithImages[0])),
        Container(width: 1, color: Colors.white30),
        Expanded(child: tile(postsWithImages[1])),
      ],
    );
  }

  return Column(
    children: [
      Expanded(
        child: Row(
          children: [
            Expanded(child: tile(postsWithImages[0])),
            Container(width: 1, color: Colors.white30),
            Expanded(child: tile(postsWithImages[1])),
          ],
        ),
      ),
      Container(height: 1, color: Colors.white30),
      Expanded(
        child: Row(
          children: [
            Expanded(child: tile(postsWithImages[2])),
            if (postsWithImages.length > 3) ...[
              Container(width: 1, color: Colors.white30),
              Expanded(child: tile(postsWithImages[3])),
            ] else
              Expanded(
                child: Container(
                  color:
                      isDarkTheme ? Colors.grey.shade700 : Colors.grey.shade300,
                  child: const Icon(Icons.folder, color: Colors.white54),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _SharedFolderPatternPainter extends CustomPainter {
  final bool isDarkTheme;

  const _SharedFolderPatternPainter({required this.isDarkTheme});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDarkTheme ? Colors.white : Colors.black).withOpacity(0.05)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(
        Offset(size.width * (0.12 + i * 0.14), size.height * 0.28),
        18 + (i % 3) * 6,
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * (0.04 + i * 0.15),
            size.height * 0.58,
            62,
            34,
          ),
          const Radius.circular(12),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SharedFolderPatternPainter oldDelegate) {
    return oldDelegate.isDarkTheme != isDarkTheme;
  }
}

Future<bool?> _showImportPrompt(
  BuildContext context, {
  required Map<String, dynamic> item,
  required bool isDarkTheme,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _SharedImportPromptDialog(
      item: item,
      isDarkTheme: isDarkTheme,
      pageContext: context,
    ),
  );
}

class _SharedImportPromptDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isDarkTheme;
  final BuildContext pageContext;

  const _SharedImportPromptDialog({
    required this.item,
    required this.isDarkTheme,
    required this.pageContext,
  });

  @override
  State<_SharedImportPromptDialog> createState() =>
      _SharedImportPromptDialogState();
}

class _SharedImportPromptDialogState extends State<_SharedImportPromptDialog> {
  Map<String, dynamic>? _previewData;
  bool _loadingPreview = true;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final shareId = widget.item['id']?.toString().trim() ?? '';
    if (shareId.isEmpty) {
      if (mounted) setState(() => _loadingPreview = false);
      return;
    }

    try {
      final preview =
          await DataService.instance.previewSharedResource(shareId);
      if (!mounted) return;
      setState(() {
        _previewData = _mergeSharedPreviewData(widget.item, preview);
        _loadingPreview = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewData = _originalData(widget.item);
          _loadingPreview = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.item['type']?.toString() ?? 'post';
    final ownerName = widget.item['ownerName']?.toString() ?? 'un utente';
    final originalData =
        _previewData ?? _mergeSharedPreviewData(widget.item, null);
    final title = _sharedItemTitle({
      ...widget.item,
      'originalData': originalData,
    });
    final isFolder = type == 'folder';
    final backgroundColor =
        widget.isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = widget.isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = widget.isDarkTheme ? Colors.white70 : Colors.black54;

    return AlertDialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(
            isFolder ? Icons.folder_shared : Icons.article,
            color: isFolder ? Colors.amber.shade700 : Colors.blue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Contenuto condiviso',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$ownerName ti ha condiviso ${isFolder ? 'la cartella' : 'il post'}:',
              style: TextStyle(color: subtitleColor, height: 1.35),
            ),
            const SizedBox(height: 12),
            if (_loadingPreview)
              AspectRatio(
                aspectRatio: isFolder ? 1.45 : 2.4,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.isDarkTheme
                        ? Colors.grey.shade800
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else
              _buildSharedItemPreview(
                originalData,
                title: title,
                isFolder: isFolder,
                isDarkTheme: widget.isDarkTheme,
              ),
            const SizedBox(height: 14),
            if (_isImporting)
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Importazione in corso...',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                'Vuoi importarlo nel tuo account?',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Più tardi'),
        ),
        TextButton(
          onPressed: _isImporting
              ? null
              : () async {
                  final rejected =
                      await _rejectSharedItem(context, widget.item);
                  if (rejected && context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
          child: const Text('Rifiuta', style: TextStyle(color: Colors.red)),
        ),
        ElevatedButton(
          onPressed: _isImporting || _loadingPreview
              ? null
              : () => _handleImport(context, isFolder: isFolder),
          child: const Text('Importa'),
        ),
      ],
    );
  }

  Future<void> _handleImport(
    BuildContext dialogContext, {
    required bool isFolder,
  }) async {
    final destination = await _chooseImportDestination(
      dialogContext,
      isFolder: isFolder,
      isDarkTheme: widget.isDarkTheme,
    );
    if (destination == null || !dialogContext.mounted) return;

    final itemId = widget.item['id']?.toString() ?? '';
    if (itemId.isNotEmpty) {
      SharedItemsPage._importsInProgress.add(itemId);
    }
    setState(() => _isImporting = true);

    try {
      String? importedFolderId;
      if (isFolder) {
        importedFolderId = await DataService.instance.acceptSharedItem(
          widget.item,
          targetParentFolderId: destination.folderId == _homeDestination
              ? null
              : destination.folderId,
        );
      } else {
        importedFolderId = await DataService.instance.acceptSharedItem(
          widget.item,
          targetFolderId: destination.folderId,
        );
      }
      if (itemId.isNotEmpty) {
        SharedItemsPage._importsInProgress.remove(itemId);
      }
      if (!dialogContext.mounted) return;
      Navigator.of(dialogContext).pop(true);
      ScaffoldMessenger.of(widget.pageContext).showSnackBar(
        const SnackBar(
          content: Text('Contenuto importato correttamente!'),
          backgroundColor: Colors.green,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.pageContext.mounted) {
          _openImportedFolder(
            widget.pageContext,
            importedFolderId,
            isDarkTheme: widget.isDarkTheme,
          );
        }
      });
    } catch (e) {
      if (itemId.isNotEmpty) {
        SharedItemsPage._importsInProgress.remove(itemId);
      }
      if (!dialogContext.mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text(_readableError(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> _openImportedFolder(
  BuildContext context,
  String? folderId, {
  required bool isDarkTheme,
}) async {
  if (folderId == null || folderId.isEmpty || !context.mounted) return;

  final folderService = FolderService();
  try {
    DataService.instance.invalidateCache(folders: true, posts: true);
    await DataService.instance.getFolders(forceRefresh: true);
    await DataService.instance.getPosts();
    await folderService.syncWithDataService();
  } catch (_) {
    try {
      DataService.instance.invalidateCache(folders: true, posts: true);
      await folderService.initializeFolders();
    } catch (_) {}
  }
  if (!context.mounted) return;

  MockFolder? target;
  void visit(MockFolder folder) {
    if (target != null) return;
    if (folder.id == folderId) {
      target = folder;
      return;
    }
    for (final child in folder.children) {
      visit(child);
    }
  }

  for (final folder in folderService.folders) {
    visit(folder);
  }

  final targetFolder = target;
  if (targetFolder == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FolderDetailPage(
        folder: targetFolder,
        isDarkTheme: isDarkTheme,
        allFolders: folderService.folders,
        onFolderUpdated: () {},
      ),
    ),
  );
}

const String _homeDestination = '__home__';

class _ImportDestination {
  final String folderId;
  final String label;

  const _ImportDestination(this.folderId, this.label);
}

Future<_ImportDestination?> _chooseImportDestination(
  BuildContext context, {
  required bool isFolder,
  required bool isDarkTheme,
}) async {
  final folders = await DataService.instance.getFolders(forceRefresh: true);
  if (!context.mounted) return null;

  final rootFolders = folders
      .where((folder) =>
          !folder.isDefault &&
          (folder.parentId == null || folder.parentId!.isEmpty))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final defaultFolders = folders.where((folder) => folder.isDefault).toList();
  final defaultFolder = defaultFolders.isEmpty ? null : defaultFolders.first;

  final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
  final textColor = isDarkTheme ? Colors.white : Colors.black87;
  final subtitleColor = isDarkTheme ? Colors.white70 : Colors.black54;

  return showDialog<_ImportDestination>(
    context: context,
    builder: (dialogContext) {
      final expandedFolderIds = <String>{};
      _ImportDestination? selectedDestination;
      var isClosing = false;

      return StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: backgroundColor,
          title: Text(
            isFolder ? 'Dove importare la cartella?' : 'Dove salvare il post?',
            style: TextStyle(color: textColor),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  selected: selectedDestination?.folderId ==
                      (isFolder
                          ? _homeDestination
                          : (defaultFolder?.id ?? 'all_folder')),
                  selectedTileColor: Colors.green.withOpacity(0.12),
                  leading: Icon(
                    isFolder ? Icons.home_outlined : Icons.all_inbox,
                    color: Colors.green,
                  ),
                  title: Text(
                    isFolder ? 'Home' : 'Tutti',
                    style: TextStyle(color: textColor),
                  ),
                  subtitle: Text(
                    isFolder
                        ? 'Crea la cartella condivisa nella Home'
                        : 'Salva il post nella cartella Tutti',
                    style: TextStyle(color: subtitleColor),
                  ),
                  trailing: selectedDestination?.folderId ==
                          (isFolder
                              ? _homeDestination
                              : (defaultFolder?.id ?? 'all_folder'))
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () {
                    setDialogState(
                      () => selectedDestination = _ImportDestination(
                        isFolder
                            ? _homeDestination
                            : (defaultFolder?.id ?? 'all_folder'),
                        isFolder ? 'Home' : 'Tutti',
                      ),
                    );
                  },
                ),
                const Divider(),
                if (rootFolders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      'Non hai ancora cartelle personali.',
                      style: TextStyle(color: subtitleColor),
                    ),
                  )
                else
                  ...rootFolders.map(
                    (folder) => _buildFolderDestinationNode(
                      dialogContext,
                      folder: folder,
                      allFolders: folders,
                      expandedFolderIds: expandedFolderIds,
                      isFolderImport: isFolder,
                      textColor: textColor,
                      subtitleColor: subtitleColor,
                      level: 0,
                      selectedDestination: selectedDestination,
                      onDestinationSelected: (destination) {
                        setDialogState(
                          () => selectedDestination = destination,
                        );
                      },
                      setDialogState: setDialogState,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isClosing
                  ? null
                  : () {
                      setDialogState(() => isClosing = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      });
                    },
              child: const Text('Annulla'),
            ),
            ElevatedButton.icon(
              onPressed: selectedDestination == null || isClosing
                  ? null
                  : () {
                      final destination = selectedDestination;
                      setDialogState(() => isClosing = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(destination);
                        }
                      });
                    },
              icon: const Icon(Icons.check),
              label: Text(
                selectedDestination == null ? 'Seleziona cartella' : 'Conferma',
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _buildFolderDestinationNode(
  BuildContext dialogContext, {
  required Folder folder,
  required List<Folder> allFolders,
  required Set<String> expandedFolderIds,
  required bool isFolderImport,
  required Color textColor,
  required Color subtitleColor,
  required int level,
  required _ImportDestination? selectedDestination,
  required ValueChanged<_ImportDestination> onDestinationSelected,
  required void Function(void Function()) setDialogState,
}) {
  final children = _childFolders(folder.id, allFolders);
  final isExpanded = expandedFolderIds.contains(folder.id);
  final isSelected = selectedDestination?.folderId == folder.id;

  if (children.isEmpty) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          selected: isSelected,
          selectedTileColor: Colors.green.withOpacity(0.12),
          contentPadding: EdgeInsets.only(left: 16.0 + (level * 18), right: 16),
          leading: const Icon(Icons.folder, color: Colors.amber),
          title: Text(folder.name, style: TextStyle(color: textColor)),
          subtitle: isFolderImport
              ? Text(
                  'La cartella condivisa verrà creata qui dentro',
                  style: TextStyle(color: subtitleColor),
                )
              : null,
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: Colors.green)
              : null,
          onTap: () => onDestinationSelected(
            _ImportDestination(folder.id, folder.name),
          ),
        ),
      ],
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        selected: isSelected,
        selectedTileColor: Colors.green.withOpacity(0.12),
        contentPadding: EdgeInsets.only(left: 8.0 + (level * 18), right: 16),
        leading: IconButton(
          icon: Icon(
            isExpanded ? Icons.expand_less : Icons.chevron_right,
            color: textColor,
          ),
          onPressed: () {
            setDialogState(() {
              if (isExpanded) {
                expandedFolderIds.remove(folder.id);
              } else {
                expandedFolderIds.add(folder.id);
              }
            });
          },
        ),
        title: Row(
          children: [
            const Icon(Icons.folder, color: Colors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(folder.name, style: TextStyle(color: textColor)),
            ),
          ],
        ),
        subtitle: Text(
          '${children.length} sottocartell${children.length == 1 ? 'a' : 'e'}',
          style: TextStyle(color: subtitleColor, fontSize: 12),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
        onTap: () => onDestinationSelected(
          _ImportDestination(folder.id, folder.name),
        ),
      ),
      if (isExpanded)
        ...children.map(
          (child) => _buildFolderDestinationNode(
            dialogContext,
            folder: child,
            allFolders: allFolders,
            expandedFolderIds: expandedFolderIds,
            isFolderImport: isFolderImport,
            textColor: textColor,
            subtitleColor: subtitleColor,
            level: level + 1,
            selectedDestination: selectedDestination,
            onDestinationSelected: onDestinationSelected,
            setDialogState: setDialogState,
          ),
        ),
    ],
  );
}

List<Folder> _childFolders(String parentId, List<Folder> folders) {
  return folders.where((folder) => folder.parentId == parentId).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

Future<bool> _rejectSharedItem(
  BuildContext context,
  Map<String, dynamic> item,
) async {
  try {
    await DataService.instance.rejectSharedItem(item['id']?.toString() ?? '');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Condivisione rifiutata.')),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readableError(e)), backgroundColor: Colors.red),
      );
    }
    return false;
  }
}

String _readableError(Object error) {
  return error
      .toString()
      .replaceFirst('FirebaseDataException: ', '')
      .replaceFirst('Exception: ', '');
}
