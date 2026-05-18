import 'package:flutter/material.dart';
import 'package:savein/data_service.dart';
import '../utils/theme_helpers.dart';
import '../widgets/custom_bottom_nav.dart';
import '../services/folder_service.dart';
import '../models/folder.dart';

class SharedItemsPage extends StatefulWidget {
  final bool isDarkTheme;

  const SharedItemsPage({
    Key? key,
    required this.isDarkTheme,
  }) : super(key: key);

  @override
  _SharedItemsPageState createState() => _SharedItemsPageState();
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
      if (mounted) {
        setState(() {
          _sharedItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('ERRORE _loadSharedItems: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);

    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      appBar: AppBar(
        title: Text('Condivisi con me', style: TextStyle(color: themeColors.titleColor, fontWeight: FontWeight.bold)),
        backgroundColor: themeColors.mainBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: themeColors.iconColor),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _sharedItems.isEmpty
              ? _buildEmptyState(themeColors)
              : RefreshIndicator(
                  onRefresh: _loadSharedItems,
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.share_outlined, size: 64, color: themeColors.subtitleColor),
          SizedBox(height: 16),
          Text(
            'Nessun elemento condiviso',
            style: TextStyle(color: themeColors.titleColor, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Gli elementi condivisi dagli altri utenti appariranno qui.',
            style: TextStyle(color: themeColors.subtitleColor, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadSharedItems,
            child: Text('Aggiorna'),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedItemCard(Map<String, dynamic> item, ThemeColors themeColors) {
    final type = item['type'];
    final ownerName = item['ownerName'];
    final originalData = item['originalData'] as Map<String, dynamic>;
    final title = type == 'post' ? originalData['title'] : originalData['name'];
    final color = type == 'folder' ? _parseColor(originalData['color']) : Colors.blue;

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      color: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.all(16),
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
          title ?? 'Senza titolo',
          style: TextStyle(color: themeColors.textColor, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(
              'Condiviso da $ownerName',
              style: TextStyle(color: themeColors.subtitleColor, fontSize: 12),
            ),
            if (type == 'post' && originalData['description'] != null)
              Text(
                originalData['description'],
                style: TextStyle(color: themeColors.hintColor, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.check, color: Colors.green),
              onPressed: () => _acceptItem(item),
              tooltip: 'Accetta',
            ),
            IconButton(
              icon: Icon(Icons.close, color: Colors.red),
              onPressed: () => _rejectItem(item),
              tooltip: 'Rifiuta',
            ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(dynamic colorData) {
    if (colorData is String) {
      try {
        return Color(int.parse(colorData.replaceAll('#', '0xFF')));
      } catch (_) {
        return Colors.blue;
      }
    } else if (colorData is int) {
      return Color(colorData);
    }
    return Colors.blue;
  }

  Future<void> _acceptItem(Map<String, dynamic> item) async {
    String? targetFolderId;
    
    if (item['type'] == 'post') {
      // Chiedi in quale cartella salvare il post
      final folderService = FolderService();
      final folders = folderService.folders.where((f) => !f.isSpecial).toList();
      
      targetFolderId = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Scegli cartella'),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: folders.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    leading: Icon(Icons.all_inbox),
                    title: Text('Tutti'),
                    onTap: () => Navigator.pop(context, 'all_folder'),
                  );
                }
                final folder = folders[index - 1];
                return ListTile(
                  leading: Icon(Icons.folder, color: folder.color),
                  title: Text(folder.name),
                  onTap: () => Navigator.pop(context, folder.id),
                );
              },
            ),
          ),
        ),
      );
      
      if (targetFolderId == null) return;
    }

    try {
      await DataService.instance.acceptSharedItem(item, targetFolderId: targetFolderId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Elemento accettato e salvato!'), backgroundColor: Colors.green),
      );
      _loadSharedItems();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante l\'accettazione: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rejectItem(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rifiuta condivisione'),
        content: Text('Sei sicuro di voler rifiutare questo elemento? Verrà rimosso dalla lista.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Rifiuta', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DataService.instance.rejectSharedItem(item['id']);
        _loadSharedItems();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
