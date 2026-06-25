import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:savein/models/folder.dart';
import 'package:savein/services/plan_limits_service.dart';
import '../services/folder_service.dart'; // Import per MockPost
import 'folder_management.dart';

// Helper class per i dialoghi dell'app
class DialogHelpers {
  // Dialog per creare una nuova cartella
  static void showCreateFolderDialog(
    BuildContext context,
    bool isDarkTheme,
    Function(String) onCreateFolder,
  ) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final fieldColor =
        isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade100;
    final hintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Nuova cartella',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              style: TextStyle(color: textColor),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Nome cartella',
                hintStyle: TextStyle(color: hintColor),
                filled: true,
                fillColor: fieldColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: hintColor)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                onCreateFolder(controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: Text('Crea',
                style:
                    TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Dialog per rinominare una cartella
  static void showRenameFolderDialog(
    BuildContext context,
    bool isDarkTheme,
    MockFolder folder,
    Function(String) onRenameFolder,
  ) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final fieldColor =
        isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade100;
    final hintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    final TextEditingController controller =
        TextEditingController(text: folder.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Rinomina cartella',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              style: TextStyle(color: textColor),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Nome cartella',
                hintStyle: TextStyle(color: hintColor),
                filled: true,
                fillColor: fieldColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: hintColor)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                onRenameFolder(controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: Text('Salva',
                style:
                    TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Dialog per eliminare una cartella
  static void showDeleteFolderDialog(
    BuildContext context,
    bool isDarkTheme,
    MockFolder folder,
    VoidCallback onDeleteFolder,
  ) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;
    final hintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Elimina cartella',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Sei sicuro di voler eliminare la cartella "${folder.name}"?\n\n'
          '⚠️ Verranno eliminate TUTTE le sottocartelle\n'
          '✅ I post rimarranno accessibili in "Tutti"',
          style: TextStyle(color: subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: hintColor)),
          ),
          TextButton(
            onPressed: () {
              onDeleteFolder();
              Navigator.pop(context);
            },
            child: Text('Elimina',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Dialog CORRETTO per spostare cartelle con selezione + conferma
  static void showMoveFolderDialog(
    BuildContext context,
    bool isDarkTheme,
    MockFolder folderToMove,
    List<MockFolder> allFolders,
    Function(MockFolder?) onMoveFolder,
  ) {
    if (folderToMove.isSpecial) {
      return;
    }

    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;
    final hintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    showDialog(
      context: context,
      builder: (context) => _MoveDialogWidget(
        backgroundColor: backgroundColor,
        textColor: textColor,
        subtitleColor: subtitleColor,
        hintColor: hintColor,
        folderToMove: folderToMove,
        allFolders: allFolders,
        onMoveFolder: onMoveFolder,
      ),
    );
  }

  // Dialog per spostare POST con selezione + conferma (simile a quello delle cartelle)
  static void showMovePostDialog(
    BuildContext context,
    bool isDarkTheme,
    MockPost postToMove,
    List<MockFolder> allFolders,
    Function(MockFolder?) onMovePost, {
    bool isMultipleSelection = false,
    int selectedCount = 1,
  }) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;
    final hintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    showDialog(
      context: context,
      builder: (context) => _MovePostDialogWidget(
        backgroundColor: backgroundColor,
        textColor: textColor,
        subtitleColor: subtitleColor,
        hintColor: hintColor,
        postToMove: postToMove,
        allFolders: allFolders,
        onMovePost: onMovePost,
        isMultipleSelection: isMultipleSelection,
        selectedCount: selectedCount,
      ),
    );
  }

  // Dialog generico di conferma
  static void showConfirmDialog(
    BuildContext context,
    bool isDarkTheme,
    String title,
    String content,
    VoidCallback onConfirm, {
    String confirmText = 'Conferma',
    String cancelText = 'Annulla',
    Color? confirmColor,
  }) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = isDarkTheme ? Colors.grey.shade300 : Colors.black54;
    final hintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(title, style: TextStyle(color: textColor)),
        content: Text(content, style: TextStyle(color: subtitleColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(cancelText, style: TextStyle(color: hintColor)),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(context);
            },
            child: Text(confirmText,
                style: TextStyle(
                    color: confirmColor ?? Colors.blue,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Dialog per condividere un elemento (post o cartella)
  static void showShareItemDialog(
    BuildContext context,
    bool isDarkTheme,
    String type, // 'post' o 'folder'
    String title,
    Future<void> Function(String) onShare, {
    String? systemShareContent,
    Future<String> Function()? systemShareContentBuilder,
    Future<bool> Function()? canStartShare,
    String? previewImageUrl,
    List<MockPost> folderPreviewPosts = const [],
  }) {
    final backgroundColor = isDarkTheme ? Colors.grey.shade900 : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final fieldColor =
        isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade100;
    final hintColor = isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600;

    final TextEditingController controller = TextEditingController();
    bool isLoading = false;
    String? error;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.share, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Condividi ${type == 'post' ? 'Post' : 'Cartella'}',
                  style:
                      TextStyle(color: textColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShareDialogPreview(
                title: title,
                type: type,
                isDarkTheme: isDarkTheme,
                previewImageUrl: previewImageUrl,
                folderPreviewPosts: folderPreviewPosts,
              ),
              SizedBox(height: 16),
              if (systemShareContent != null ||
                  systemShareContentBuilder != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isLoading
                        ? null
                        : () async {
                            final allowed = await (canStartShare?.call() ??
                                Future.value(true));
                            if (!allowed) return;

                            setDialogState(() {
                              isLoading = true;
                              error = null;
                            });
                            try {
                              final content = systemShareContentBuilder != null
                                  ? await systemShareContentBuilder()
                                  : systemShareContent!;
                              final result = await SharePlus.instance.share(
                                ShareParams(text: content),
                              );
                              if (result.status == ShareResultStatus.success) {
                                await PlanLimitsService.recordFeatureSuccess(
                                  type == 'post'
                                      ? 'share_post'
                                      : 'share_folder',
                                );
                              } else {
                                if (context.mounted) {
                                  setDialogState(() {
                                    isLoading = false;
                                  });
                                }
                                return;
                              }
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted) {
                                setDialogState(() {
                                  isLoading = false;
                                  error = e
                                      .toString()
                                      .replaceFirst('Exception: ', '');
                                });
                              }
                            }
                          },
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.message_outlined),
                    label: Text(isLoading
                        ? 'Creo il link...'
                        : 'Invia tramite messaggio'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: BorderSide(color: Colors.blue),
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider(color: hintColor.withOpacity(0.5))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('oppure tramite email',
                          style: TextStyle(color: hintColor, fontSize: 12)),
                    ),
                    Expanded(child: Divider(color: hintColor.withOpacity(0.5))),
                  ],
                ),
                SizedBox(height: 16),
              ],
              TextField(
                controller: controller,
                style: TextStyle(color: textColor),
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Email del destinatario',
                  hintStyle: TextStyle(color: hintColor),
                  filled: true,
                  fillColor: fieldColor,
                  errorText: error,
                  prefixIcon: Icon(Icons.email_outlined, color: hintColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                autofocus: systemShareContent == null &&
                    systemShareContentBuilder == null,
              ),
              if (isLoading)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: Text('Annulla', style: TextStyle(color: hintColor)),
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final email = controller.text.trim();
                      if (email.isEmpty) {
                        setDialogState(() => error = 'Inserisci un\'email');
                        return;
                      }

                      final allowed =
                          await (canStartShare?.call() ?? Future.value(true));
                      if (!allowed) return;

                      setDialogState(() {
                        isLoading = true;
                        error = null;
                      });

                      try {
                        await onShare(email);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Elemento condiviso con successo!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setDialogState(() {
                            isLoading = false;
                            final errStr = e.toString().toLowerCase();
                            if (errStr.contains('non trovato')) {
                              error = 'Utente non trovato';
                            } else if (errStr.contains('stesso')) {
                              error = 'Non puoi condividere con te stesso';
                            } else if (errStr.contains('disabilitata')) {
                              error =
                                  e.toString().replaceFirst('Exception: ', '');
                            } else {
                              error = e
                                  .toString()
                                  .replaceFirst('FirebaseDataException: ', '')
                                  .replaceFirst('Exception: ', '');
                            }
                          });
                        }
                      }
                    },
              child: Text('Condividi email',
                  style: TextStyle(
                      color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareDialogPreview extends StatelessWidget {
  final String title;
  final String type;
  final bool isDarkTheme;
  final String? previewImageUrl;
  final List<MockPost> folderPreviewPosts;

  const _ShareDialogPreview({
    required this.title,
    required this.type,
    required this.isDarkTheme,
    required this.previewImageUrl,
    required this.folderPreviewPosts,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade100;
    final borderColor = isDarkTheme ? Colors.white12 : Colors.black12;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: type == 'folder'
                  ? _buildFolderPreview()
                  : _buildNetworkImage(previewImageUrl),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _truncateTitle(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  type == 'folder' ? 'Cartella SaveIn' : 'Post SaveIn',
                  style: TextStyle(
                    color: isDarkTheme ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderPreview() {
    final postsWithImages = folderPreviewPosts
        .where((post) =>
            (post.previewStorageUrl ?? post.imageUrl)?.trim().isNotEmpty ==
            true)
        .take(4)
        .toList();

    if (postsWithImages.isEmpty) {
      return Container(
        color: Colors.amber.shade100,
        child: Icon(Icons.folder, color: Colors.amber.shade700, size: 34),
      );
    }

    Widget tile(MockPost post) {
      return _buildNetworkImage(post.previewStorageUrl ?? post.imageUrl);
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
              Container(width: 1, color: Colors.white30),
              Expanded(
                child: postsWithImages.length > 3
                    ? tile(postsWithImages[3])
                    : Container(
                        color: Colors.amber.shade100,
                        child: Icon(
                          Icons.folder,
                          color: Colors.amber.shade700,
                          size: 22,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkImage(String? url) {
    final imageUrl = url?.trim();
    if (imageUrl == null || imageUrl.isEmpty) {
      return _buildFallbackImage();
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, _) => _buildFallbackImage(showLoader: true),
      errorWidget: (context, _, __) => _buildFallbackImage(),
    );
  }

  Widget _buildFallbackImage({bool showLoader = false}) {
    return Container(
      color: isDarkTheme ? Colors.grey.shade700 : Colors.grey.shade300,
      child: Center(
        child: showLoader
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                type == 'folder' ? Icons.folder : Icons.article,
                color: isDarkTheme ? Colors.white54 : Colors.black38,
              ),
      ),
    );
  }

  String _truncateTitle(String value) {
    final clean = value.trim();
    if (clean.length <= 20) return clean;
    return '${clean.substring(0, 20)}...';
  }
}

// Widget separato per il dialog di spostamento cartelle con selezione
class _MoveDialogWidget extends StatefulWidget {
  final Color backgroundColor;
  final Color textColor;
  final Color subtitleColor;
  final Color hintColor;
  final MockFolder folderToMove;
  final List<MockFolder> allFolders;
  final Function(MockFolder?) onMoveFolder;

  const _MoveDialogWidget({
    required this.backgroundColor,
    required this.textColor,
    required this.subtitleColor,
    required this.hintColor,
    required this.folderToMove,
    required this.allFolders,
    required this.onMoveFolder,
  });

  @override
  _MoveDialogWidgetState createState() => _MoveDialogWidgetState();
}

class _MoveDialogWidgetState extends State<_MoveDialogWidget> {
  final Set<String> _expandedFolders = <String>{};
  MockFolder? _selectedDestination; // null = Home
  bool _isHomeSelected = false;

  @override
  Widget build(BuildContext context) {
    final canMove = _selectedDestination != null || _isHomeSelected;

    return AlertDialog(
      backgroundColor: widget.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        'Sposta "${widget.folderToMove.name}"',
        style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold),
      ),
      content: Container(
        width: double.maxFinite,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seleziona la destinazione:',
              style: TextStyle(color: widget.subtitleColor, fontSize: 14),
            ),
            SizedBox(height: 16),

            // Pulsante per Home/Cartella principale
            _buildHomeButton(),

            SizedBox(height: 12),
            Text(
              'Cartelle:',
              style: TextStyle(
                  color: widget.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),

            // Lista delle cartelle principali
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: _buildFolderButtons(),
                ),
              ),
            ),

            SizedBox(height: 16),

            // Pulsante di conferma CORRETTO
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canMove
                    ? () {
                        print(
                            'DEBUG: Confermando spostamento. Home selezionato: $_isHomeSelected, Destinazione: ${_selectedDestination?.name}');

                        Navigator.pop(context);

                        // CORREZIONE: Passa esplicitamente null se Home è selezionato
                        if (_isHomeSelected) {
                          print('DEBUG: Passando null per Home');
                          widget.onMoveFolder(null);
                        } else if (_selectedDestination != null) {
                          print(
                              'DEBUG: Passando destinazione: ${_selectedDestination!.name}');
                          widget.onMoveFolder(_selectedDestination);
                        } else {
                          print(
                              'ERRORE: Nessuna destinazione valida selezionata');
                        }
                      }
                    : null,
                icon: Icon(
                  Icons.check,
                  color: canMove ? Colors.white : widget.hintColor,
                  size: 20,
                ),
                label: Text(
                  _isHomeSelected
                      ? 'Sposta in Home'
                      : _selectedDestination != null
                          ? 'Sposta in "${_selectedDestination!.name}"'
                          : 'Seleziona una destinazione',
                  style: TextStyle(
                    color: canMove ? Colors.white : widget.hintColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canMove
                      ? Colors.green
                      : widget.hintColor.withOpacity(0.3),
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Annulla', style: TextStyle(color: widget.hintColor)),
        ),
      ],
    );
  }

  Widget _buildHomeButton() {
    final canMoveToHome = widget.folderToMove.level >
        0; // Può essere spostato alla home solo se non è già lì
    final isSelected = _isHomeSelected;

    print(
        'DEBUG: Building Home button. Can move to home: $canMoveToHome, Is selected: $isSelected');

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 8),
      child: ElevatedButton.icon(
        onPressed: canMoveToHome
            ? () {
                print(
                    'DEBUG: Home button pressed. Current state - Home selected: $_isHomeSelected');

                setState(() {
                  _isHomeSelected = !_isHomeSelected;
                  if (_isHomeSelected) {
                    _selectedDestination = null; // Deseleziona altre cartelle
                    print(
                        'DEBUG: Home selezionato, altre cartelle deselezionate');
                  } else {
                    print('DEBUG: Home deselezionato');
                  }
                });
              }
            : null,
        icon: Icon(
          Icons.home,
          color: isSelected
              ? Colors.white
              : canMoveToHome
                  ? Colors.black87
                  : widget.hintColor,
          size: 20,
        ),
        label: Text(
          'Home',
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : canMoveToHome
                    ? Colors.black87
                    : widget.hintColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected
              ? Colors.blue
              : canMoveToHome
                  ? Colors.grey.shade300
                  : widget.hintColor.withOpacity(0.3),
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: isSelected
                ? BorderSide(color: Colors.blue, width: 2)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFolderButtons() {
    List<Widget> buttons = [];

    // 🔥 FIX: Ordina le cartelle alfabeticamente (case-insensitive) prima di costruire i pulsanti
    final sortedFolders = List<MockFolder>.from(widget.allFolders)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    for (var folder in sortedFolders) {
      // Salta la cartella speciale "Tutti" e la cartella stessa
      if (folder.isSpecial || folder == widget.folderToMove) continue;

      // Non mostrare cartelle che sono discendenti della cartella da spostare
      if (FolderManagement.isDescendantOf(folder, widget.folderToMove))
        continue;

      buttons.add(_buildFolderButton(folder, 0));
    }

    return buttons;
  }

  Widget _buildFolderButton(MockFolder folder, int indentLevel) {
    final canMove = FolderManagement.canMoveFolder(widget.folderToMove, folder);
    final isExpanded =
        _expandedFolders.contains(folder.name + folder.level.toString());
    final hasChildren = folder.children.isNotEmpty;
    final isSelected = _selectedDestination == folder;

    return Container(
      margin: EdgeInsets.only(left: indentLevel * 20.0, bottom: 4),
      child: Column(
        children: [
          // Pulsante principale della cartella
          Container(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canMove
                  ? () {
                      setState(() {
                        if (_selectedDestination == folder) {
                          _selectedDestination =
                              null; // Deseleziona se già selezionata
                        } else {
                          _selectedDestination =
                              folder; // Seleziona questa cartella
                          _isHomeSelected = false; // Deseleziona Home
                        }

                        // 🔥 FIX: Espandi/contrai cliccando ovunque sulla riga
                        if (hasChildren) {
                          final key = folder.name + folder.level.toString();
                          if (isExpanded) {
                            _expandedFolders.remove(key);
                          } else {
                            _expandedFolders.add(key);
                          }
                        }
                      });
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected
                    ? Colors.blue
                    : canMove
                        ? folder.color
                        : widget.hintColor.withOpacity(0.3),
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: isSelected
                      ? BorderSide(color: Colors.blue, width: 2)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  // Icona espandi/contrai (solo se ha figli)
                  if (hasChildren)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          final key = folder.name + folder.level.toString();
                          if (isExpanded) {
                            _expandedFolders.remove(key);
                          } else {
                            _expandedFolders.add(key);
                          }
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          color: isSelected ? Colors.white : Colors.black87,
                          size: 18,
                        ),
                      ),
                    )
                  else
                    SizedBox(width: 26),

                  SizedBox(width: 8),

                  // Icona cartella
                  Icon(
                    hasChildren ? Icons.folder : Icons.folder_outlined,
                    color: isSelected ? Colors.white : Colors.black87,
                    size: 18,
                  ),
                  SizedBox(width: 8),

                  // Nome cartella (SOLO IL NOME)
                  Expanded(
                    child: Text(
                      folder.name,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),

                  // Icona di selezione
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),

          // Sottocartelle (se espanse)
          if (hasChildren && isExpanded)
            // 🔥 FIX: Ordina le sottocartelle alfabeticamente
            ...(List<MockFolder>.from(folder.children)
                  ..sort((a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase())))
                .where((child) =>
                    !FolderManagement.isDescendantOf(
                        child, widget.folderToMove) &&
                    child != widget.folderToMove)
                .map((child) => _buildFolderButton(child, indentLevel + 1))
                .toList(),
        ],
      ),
    );
  }
}

// Widget separato per il dialog di spostamento POST con selezione
class _MovePostDialogWidget extends StatefulWidget {
  final Color backgroundColor;
  final Color textColor;
  final Color subtitleColor;
  final Color hintColor;
  final MockPost postToMove;
  final List<MockFolder> allFolders;
  final Function(MockFolder?) onMovePost;
  final bool isMultipleSelection;
  final int selectedCount;

  const _MovePostDialogWidget({
    required this.backgroundColor,
    required this.textColor,
    required this.subtitleColor,
    required this.hintColor,
    required this.postToMove,
    required this.allFolders,
    required this.onMovePost,
    this.isMultipleSelection = false,
    this.selectedCount = 1,
  });

  @override
  _MovePostDialogWidgetState createState() => _MovePostDialogWidgetState();
}

class _MovePostDialogWidgetState extends State<_MovePostDialogWidget> {
  final Set<String> _expandedFolders = <String>{};
  MockFolder? _selectedDestination; // null = Tutti (nessuna cartella specifica)
  bool _isTuttiSelected = false;

  @override
  Widget build(BuildContext context) {
    final canMove = _selectedDestination != null || _isTuttiSelected;

    return AlertDialog(
      backgroundColor: widget.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.drive_file_move_outline, color: Colors.blue, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isMultipleSelection
                      ? 'Sposta ${widget.selectedCount} Post'
                      : 'Sposta Post',
                  style: TextStyle(
                      color: widget.textColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                    widget.isMultipleSelection
                        ? Icons.library_books
                        : Icons.article,
                    color: Colors.blue,
                    size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isMultipleSelection
                        ? '${widget.selectedCount} post selezionati'
                        : widget.postToMove.title,
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seleziona la destinazione:',
              style: TextStyle(color: widget.subtitleColor, fontSize: 14),
            ),
            SizedBox(height: 16),

            // Pulsante per "Tutti" (senza cartella specifica)
            _buildTuttiButton(),

            SizedBox(height: 12),
            Text(
              'Cartelle:',
              style: TextStyle(
                  color: widget.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),

            // Lista delle cartelle principali
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: _buildFolderButtons(),
                ),
              ),
            ),

            SizedBox(height: 16),

            // Pulsante di conferma
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canMove
                    ? () {
                        print(
                            'DEBUG: Confermando spostamento post. Tutti selezionato: $_isTuttiSelected, Destinazione: ${_selectedDestination?.name}');

                        Navigator.pop(context);

                        // Passa null se "Tutti" è selezionato, altrimenti la cartella selezionata
                        if (_isTuttiSelected) {
                          print(
                              'DEBUG: Spostando post in "Tutti" (nessuna cartella)');
                          widget.onMovePost(null);
                        } else if (_selectedDestination != null) {
                          print(
                              'DEBUG: Spostando post in cartella: ${_selectedDestination!.name}');
                          widget.onMovePost(_selectedDestination);
                        } else {
                          print(
                              'ERRORE: Nessuna destinazione valida selezionata');
                        }
                      }
                    : null,
                icon: Icon(
                  Icons.check,
                  color: canMove ? Colors.white : widget.hintColor,
                  size: 20,
                ),
                label: Text(
                  _isTuttiSelected
                      ? (widget.isMultipleSelection
                          ? 'Sposta ${widget.selectedCount} post in "Tutti"'
                          : 'Sposta in "Tutti"')
                      : _selectedDestination != null
                          ? (widget.isMultipleSelection
                              ? 'Sposta ${widget.selectedCount} post in "${_selectedDestination!.name}"'
                              : 'Sposta in "${_selectedDestination!.name}"')
                          : 'Seleziona una destinazione',
                  style: TextStyle(
                    color: canMove ? Colors.white : widget.hintColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: canMove
                      ? Colors.green
                      : widget.hintColor.withOpacity(0.3),
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Annulla', style: TextStyle(color: widget.hintColor)),
        ),
      ],
    );
  }

  Widget _buildTuttiButton() {
    final isSelected = _isTuttiSelected;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 8),
      child: ElevatedButton.icon(
        onPressed: () {
          print(
              'DEBUG: Pulsante "Tutti" premuto. Stato corrente: $_isTuttiSelected');

          setState(() {
            _isTuttiSelected = !_isTuttiSelected;
            if (_isTuttiSelected) {
              _selectedDestination = null; // Deseleziona altre cartelle
              print('DEBUG: "Tutti" selezionato, altre cartelle deselezionate');
            } else {
              print('DEBUG: "Tutti" deselezionato');
            }
          });
        },
        icon: Icon(
          Icons.all_inbox,
          color: isSelected ? Colors.white : Colors.black87,
          size: 20,
        ),
        label: Text(
          'Tutti (nessuna cartella)',
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.purple : Colors.purple.shade100,
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: isSelected
                ? BorderSide(color: Colors.purple, width: 2)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFolderButtons() {
    List<Widget> buttons = [];

    // 🔥 FIX: Ordina le cartelle alfabeticamente (case-insensitive) prima di costruire i pulsanti
    final sortedFolders = List<MockFolder>.from(widget.allFolders)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    for (var folder in sortedFolders) {
      // Salta la cartella speciale "Tutti"
      if (folder.isSpecial) continue;

      buttons.add(_buildFolderButton(folder, 0));
    }

    return buttons;
  }

  Widget _buildFolderButton(MockFolder folder, int indentLevel) {
    final isExpanded =
        _expandedFolders.contains(folder.name + folder.level.toString());
    final hasChildren = folder.children.isNotEmpty;
    final isSelected = _selectedDestination == folder;

    return Container(
      margin: EdgeInsets.only(left: indentLevel * 20.0, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pulsante cartella: cliccare espande/contrae se ha figli, altrimenti seleziona
          Container(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  if (hasChildren) {
                    // Se ha figli, espandi/contrai
                    final key = folder.name + folder.level.toString();
                    if (isExpanded) {
                      _expandedFolders.remove(key);
                    } else {
                      _expandedFolders.add(key);
                    }
                  }

                  // Seleziona/deseleziona sempre
                  if (_selectedDestination == folder) {
                    _selectedDestination = null;
                  } else {
                    _selectedDestination = folder;
                    _isTuttiSelected = false;
                  }
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected ? Colors.blue : folder.color,
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: isSelected
                      ? BorderSide(color: Colors.blue, width: 2)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  // Icona chevron integrata (se ha figli)
                  if (hasChildren)
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      color: isSelected ? Colors.white : Colors.black87,
                      size: 20,
                    ),

                  SizedBox(width: hasChildren ? 8 : 0),

                  // Icona cartella
                  Icon(
                    hasChildren ? Icons.folder : Icons.folder_outlined,
                    color: isSelected ? Colors.white : Colors.black87,
                    size: 18,
                  ),
                  SizedBox(width: 8),

                  // Nome cartella
                  Expanded(
                    child: Text(
                      folder.name,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),

                  // Icona di selezione
                  if (isSelected)
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),

          // Sottocartelle espanse
          if (hasChildren && isExpanded) ...[
            SizedBox(height: 4),
            // 🔥 FIX: Ordina le sottocartelle alfabeticamente
            ...(List<MockFolder>.from(folder.children)
                  ..sort((a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase())))
                .map((child) => _buildFolderButton(child, indentLevel + 1))
                .toList(),
          ],
        ],
      ),
    );
  }
}
