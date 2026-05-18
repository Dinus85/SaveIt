// widgets/folder_card.dart
// Widget aggiornato per le card delle cartelle con anteprime immagini
// ✨ AGGIORNATO: Ora usa UnifiedFolderManager

import 'package:flutter/material.dart';
import '../models/folder.dart';
import 'package:savein/data_service.dart';
import '../services/folder_service.dart';
import '../services/folder_management_unified.dart'; // ⭐ NUOVO
import 'package:savein/utils/dialog_helpers.dart';
import 'custom_bottom_nav.dart';
import 'post_preview_image.dart';
import 'reminder_dialog.dart';

class MockFolderCard extends StatelessWidget {
  final MockFolder folder;
  final VoidCallback onTap;
  final Function(MockFolder) onRename;
  final Function(MockFolder) onDelete;
  final Function(MockFolder) onMove;
  final List<MockFolder> allFolders;
  final bool isDarkTheme;

  const MockFolderCard({
    Key? key,
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    required this.allFolders,
    this.isDarkTheme = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final folderService = FolderService();
    
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showFolderMenu(context),
      child: Container(
        decoration: BoxDecoration(
          color: folder.isShared 
              ? Colors.blue.withOpacity(0.2) // Colore evidenziato per cartelle condivise
              : (folder.color?.withOpacity(0.15) ?? Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: folder.isShared ? Colors.blue : Colors.black, 
            width: folder.isShared ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 🆕 AGGIORNATO: Anteprima con immagini degli ultimi post
            Positioned.fill(
              child: _buildFolderPreview(folderService),
            ),
            
            // Gradiente overlay per leggibilità 
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.2),
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
              ),
            ),
            
            // Contenuto della card
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end, // Spinge tutto in basso
                  children: [
                    // Icona cartella
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: folder.color?.withOpacity(0.9) ?? Colors.blue.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        folder.isSpecial ? Icons.folder_special : Icons.folder,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    
                    SizedBox(height: 8),
                    
                    // Nome cartella
                    Text(
                      folder.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 2,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    SizedBox(height: 2),
                    
                    // Conteggio
                    Text(
                      folder.count,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 2,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            // 🆕 Menu e Share spostati fuori dalla Column per evitare overflow
            if (!folder.isSpecial)
              Positioned(
                top: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _showFolderMenu(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.8),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _shareFolder(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.share,
                          color: Colors.white,
                          size: 18,
                        ),
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

  // 🆕 COMPLETAMENTE RISCRITTO: Anteprima cartella con immagini
  Widget _buildFolderPreview(FolderService folderService) {
    // 🆕 STEP 1: Ottieni ultimi 4 post con immagini
    final postsWithImages = folderService.getLastPostsWithImagesForFolder(folder, maxPosts: 4);
    
    
    if (postsWithImages.isNotEmpty) {
      // 🆕 STEP 2: Mostra griglia immagini se disponibili
      return _PostImagesGrid(
        posts: postsWithImages,
        borderRadius: BorderRadius.circular(12),
      );
    } else {
      // 🆕 STEP 3: Fallback al comportamento originale se nessuna immagine
      return _buildOriginalPreview(folderService);
    }
  }

  // 🆕 NUOVO: Mantiene l'anteprima originale per cartelle senza immagini
  Widget _buildOriginalPreview(FolderService folderService) {
    // Ottieni l'ultimo post ricorsivamente (incluse sottocartelle)
    final lastPost = folderService.getLastPostInFolderRecursive(folder);
    
    if (lastPost == null) {
      // Nessun post: mostra pattern di default
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              folder.color?.withOpacity(0.3) ?? Colors.blue.withOpacity(0.3),
              folder.color?.withOpacity(0.1) ?? Colors.blue.withOpacity(0.1),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.folder_outlined,
            color: folder.color?.withOpacity(0.5) ?? Colors.blue.withOpacity(0.5),
            size: 48,
          ),
        ),
      );
    }
    
    // Mostra anteprima basata sull'ultimo post
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: _getPreviewColorFromPost(lastPost),
      ),
      child: Stack(
        children: [
          // Pattern di sfondo
          Positioned.fill(
            child: CustomPaint(
              painter: _PostPreviewPainter(lastPost),
            ),
          ),
          
          // Icona sociale in basso a destra
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                _getIconFromPost(lastPost),
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPreviewColorFromPost(MockPost post) {
    final domain = Uri.tryParse(post.url)?.host.toLowerCase() ?? '';
    
    if (domain.contains('youtube.com') || domain.contains('youtu.be')) {
      return Color(0xFFFF0000);
    } else if (domain.contains('github.com')) {
      return Color(0xFF24292e);
    } else if (domain.contains('flutter.dev')) {
      return Color(0xFF02569B);
    } else if (domain.contains('giallozafferano.it')) {
      return Color(0xFFE17B47);
    } else if (domain.contains('instagram.com')) {
      return Color(0xFFE4405F);
    } else if (domain.contains('twitter.com') || domain.contains('x.com')) {
      return Color(0xFF1DA1F2);
    } else {
      // Colore basato sul dominio con hash
      return _getColorFromDomain(domain);
    }
  }

  IconData _getIconFromPost(MockPost post) {
    final domain = Uri.tryParse(post.url)?.host.toLowerCase() ?? '';
    
    if (domain.contains('youtube.com') || domain.contains('youtu.be')) {
      return Icons.play_circle_filled;
    } else if (domain.contains('github.com')) {
      return Icons.code;
    } else if (domain.contains('flutter.dev')) {
      return Icons.phone_android;
    } else if (domain.contains('instagram.com')) {
      return Icons.camera_alt;
    } else if (domain.contains('twitter.com') || domain.contains('x.com')) {
      return Icons.comment;
    } else {
      return Icons.link;
    }
  }

  Color _getColorFromDomain(String domain) {
    if (domain.isEmpty) return Colors.grey;
    
    final colors = [
      Colors.blue.shade500,
      Colors.green.shade500,
      Colors.orange.shade500,
      Colors.purple.shade500,
      Colors.red.shade500,
      Colors.teal.shade500,
    ];
    
    final hash = domain.hashCode;
    return colors[hash.abs() % colors.length];
  }

  void _showFolderMenu(BuildContext context) {
    if (folder.isSpecial) return; // Non mostrare menu per cartelle speciali
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeModalBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: folder.color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.folder, color: Colors.white, size: 16),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          folder.count,
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            _buildMenuOption(Icons.edit, 'Rinomina', Colors.blue, () {
              Navigator.pop(context);
              onRename(folder);
            }),
            
            _buildMenuOption(Icons.drive_file_move_outline, 'Sposta', Colors.orange, () {
              Navigator.pop(context);
              onMove(folder);
            }),
            
            _buildMenuOption(Icons.notifications_none, 'Reminder', Colors.orange, () {
              Navigator.pop(context);
              _showFolderReminderDialog(context);
            }),
            
            _buildMenuOption(Icons.share, 'Condividi', Colors.blue, () {
              Navigator.pop(context);
              _shareFolder(context);
            }),
            
            _buildMenuOption(Icons.delete_outline, 'Elimina', Colors.red, () {
              Navigator.pop(context);
              onDelete(folder);
            }),
            
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
  

  void _showFolderReminderDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ReminderDialog.forFolder(
        folderId: folder.id ?? '',
        folderName: folder.name,
        isDarkTheme: isDarkTheme,
      ),
    );
  }

  Widget _buildMenuOption(IconData icon, String title, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  void _shareFolder(BuildContext context) async {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    
    // Mostra un caricamento se necessario, ma qui recuperiamo i post per il sistema di condivisione
    final allPosts = await DataService.instance.getPosts();
    final folderPosts = allPosts.where((p) => p.folderId == folder.id).toList();
    
    String shareContent = 'Cartella: ${folder.name}\n\n';
    if (folderPosts.isEmpty) {
      shareContent += 'Questa cartella è vuota.';
    } else {
      for (var i = 0; i < folderPosts.length; i++) {
        shareContent += '${i + 1}. ${folderPosts[i].title}\n${folderPosts[i].url}\n\n';
      }
    }
    shareContent += 'Inviato tramite SaveIn';

    if (context.mounted) {
      DialogHelpers.showShareItemDialog(
        context,
        isDarkTheme,
        'folder',
        folder.name,
        (email) async {
          final realFolders = await DataService.instance.getFolders();
          final folderToShare = realFolders.firstWhere((f) => f.id == folder.id || f.name == folder.name);
          await DataService.instance.shareFolder(folderToShare, email);
        },
        systemShareContent: shareContent,
      );
    }
  }
}

// 🆕 NUOVO: Widget per griglia di immagini degli ultimi post
class _PostImagesGrid extends StatelessWidget {
  final List<MockPost> posts;
  final BorderRadius borderRadius;

  const _PostImagesGrid({
    Key? key,
    required this.posts,
    required this.borderRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: Colors.grey.shade100,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: _buildImageLayout(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey.shade200,
            Colors.grey.shade100,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.photo_library_outlined,
          color: Colors.grey.shade400,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildImageLayout() {
    switch (posts.length) {
      case 1:
        return _buildSingleImage();
      case 2:
        return _buildTwoImages();
      case 3:
        return _buildThreeImages();
      default:
        return _buildFourImages();
    }
  }

  // Layout per 1 immagine - occupa tutto lo spazio
  Widget _buildSingleImage() {
    return _ImageTile(
      post: posts[0],
      fit: BoxFit.cover,
    );
  }

  // Layout per 2 immagini - disposte verticalmente
  Widget _buildTwoImages() {
    return Column(
      children: [
        Expanded(
          child: _ImageTile(
            post: posts[0],
            fit: BoxFit.cover,
          ),
        ),
        Container(height: 1, color: Colors.white.withOpacity(0.3)),
        Expanded(
          child: _ImageTile(
            post: posts[1],
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }

  // Layout per 3 immagini - 2 in alto, 1 in basso
  Widget _buildThreeImages() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _ImageTile(
                  post: posts[0],
                  fit: BoxFit.cover,
                ),
              ),
              Container(width: 1, color: Colors.white.withOpacity(0.3)),
              Expanded(
                child: _ImageTile(
                  post: posts[1],
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: Colors.white.withOpacity(0.3)),
        Expanded(
          child: _ImageTile(
            post: posts[2],
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }

  // Layout per 4+ immagini - griglia 2x2
  Widget _buildFourImages() {
    final p0 = posts[0];
    final p1 = posts[1];
    final p2 = posts[2];
    final p3 = posts.length > 3 ? posts[3] : posts[2];
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _ImageTile(
                  post: p0,
                  fit: BoxFit.cover,
                ),
              ),
              Container(width: 1, color: Colors.white.withOpacity(0.3)),
              Expanded(
                child: _ImageTile(
                  post: p1,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: Colors.white.withOpacity(0.3)),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _ImageTile(
                  post: p2,
                  fit: BoxFit.cover,
                ),
              ),
              Container(width: 1, color: Colors.white.withOpacity(0.3)),
              Expanded(
                child: _ImageTile(
                  post: p3,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 🆕 NUOVO: Widget per singola immagine con cache persistente locale
class _ImageTile extends StatefulWidget {
  final MockPost post;
  final BoxFit fit;

  const _ImageTile({
    Key? key,
    required this.post,
    required this.fit,
  }) : super(key: key);

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: ClipRect(
        child: PostPreviewImage(
          postId: widget.post.id,
          imageUrl: widget.post.imageUrl,
          remoteImageUrl: widget.post.previewStorageUrl,
          fit: widget.fit,
        ),
      ),
    );
  }
}

// Painter personalizzato per pattern di anteprima basato sul post (MANTETTO ORIGINALE)
class _PostPreviewPainter extends CustomPainter {
  final MockPost post;

  _PostPreviewPainter(this.post);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    // Crea un pattern basato sul titolo del post
    final hash = post.title.hashCode;
    
    // Pattern a rete
    for (int i = 0; i < 5; i++) {
      for (int j = 0; j < 5; j++) {
        if ((i + j + hash) % 3 == 0) {
          final rect = Rect.fromLTWH(
            i * size.width / 5,
            j * size.height / 5,
            size.width / 6,
            size.height / 6,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(2)),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}