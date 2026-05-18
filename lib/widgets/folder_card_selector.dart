import 'package:flutter/material.dart';
import '../models/folder.dart';
import '../services/access_control_service.dart';
import '../services/folder_service.dart';
import '../data_service.dart';
import '../utils/folder_management.dart';
import '../utils/constants.dart';

class FolderCardSelector extends StatefulWidget {
  final Function(String) onFolderSelected;
  final Function(String, String?) onCreateFolder;
  final Function(String, String?)? onTemporaryFolderCreated;
  final bool isDarkTheme;
  final String? initialSelection;

  const FolderCardSelector({
    Key? key,
    required this.onFolderSelected,
    required this.onCreateFolder,
    this.onTemporaryFolderCreated,
    required this.isDarkTheme,
    this.initialSelection,
  }) : super(key: key);

  @override
  _FolderCardSelectorState createState() => _FolderCardSelectorState();
}

class _FolderCardSelectorState extends State<FolderCardSelector> {
  final AppAccessService _accessService = AppAccessService();
  final FolderService _folderService = FolderService();
  final TextEditingController _searchController = TextEditingController();

  List<String> _currentPath = [];
  List<MockFolder> _currentFolders = [];
  List<MockFolder> _allFolders = [];
  String? _selectedFolderPath = '';

  bool _isSearching = false;
  List<MockFolder> _searchResults = [];

  bool _isLoading = true;

  List<MockFolder> _localTemporaryFolders = [];
  // 🔥 FIX: Usa il percorso completo come chiave per supportare cartelle con lo stesso nome in posizioni diverse
  Map<String, String> _temporaryFolderPaths =
      {}; // Key: fullPath (es: "Home › A › B"), Value: parentPath (es: "Home › A")

  late Color _mainBackgroundColor;
  late Color _textColor;
  late Color _subtitleColor;
  late Color _iconColor;

  @override
  void initState() {
    super.initState();

    _selectedFolderPath = widget.initialSelection ?? '';
    _searchController.addListener(_onSearchChanged);

    _initializeColors();
    _loadAllFolders();
  }

  void _initializeColors() {
    _mainBackgroundColor =
        widget.isDarkTheme ? Color(0xFF1a1a1a) : Color(0xFFF0F8F0);
    _textColor = widget.isDarkTheme ? Colors.white : Colors.black87;
    _subtitleColor = widget.isDarkTheme ? Colors.white70 : Colors.black54;
    _iconColor = widget.isDarkTheme ? Colors.white70 : Colors.black54;
  }

  Future<void> _loadAllFolders() async {
    // 🔥 FIX: Controlla mounted prima di setState
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      await _folderService.syncWithDataService();
      final allFolders = _folderService.folders;

      // 🔥 FIX: Controlla mounted dopo operazione asincrona
      if (mounted) {
        setState(() {
          _allFolders = allFolders;
          _currentFolders = _sortFolders(allFolders);
          _currentPath = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      // 🔥 FIX: Controlla mounted prima di setState
      if (mounted) {
        setState(() {
          _allFolders = [];
          _currentFolders = [];
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    // 🔥 FIX: Controlla mounted all'inizio
    if (!mounted) return;

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults.clear();
          _currentFolders = _combineRealAndTemporaryFolders(_allFolders);
        });
      }
      return;
    }

    // 🔥 FIX: Controlla mounted prima di setState
    if (mounted) {
      setState(() {
        _isSearching = true;
        final allCombined = _combineRealAndTemporaryFolders(_allFolders);
        final results = allCombined.where((folder) {
          return folder.name.toLowerCase().contains(query.toLowerCase());
        }).toList();
        // Ordina anche i risultati della ricerca
        _searchResults = _sortFolders(results);
        _currentFolders = _searchResults;
      });
    }
  }

  // 🔥 FIX: Helper per generare una chiave unica per ogni cartella temporanea
  String _getTempFolderKey(String folderName, String parentPath) {
    return parentPath.isEmpty ? folderName : '$parentPath › $folderName';
  }

  List<MockFolder> _combineRealAndTemporaryFolders(
      List<MockFolder> realFolders) {
    final combined = List<MockFolder>.from(realFolders);

    // Solo cartelle temporanee ROOT (livello 0) nella homepage
    for (var tempFolder in _localTemporaryFolders) {
      final tempParentPath = _temporaryFolderPaths[tempFolder.name] ?? '';
      final isRootTemporaryFolder = tempParentPath.isEmpty;

      if (isRootTemporaryFolder) {
        if (!combined.any(
            (f) => f.name == tempFolder.name && f.level == tempFolder.level)) {
          combined.add(tempFolder);
        }
      }
    }

    // Ordina alfabeticamente, mantenendo "Tutti" in prima posizione
    return _sortFolders(combined);
  }

  Future<void> _navigateToFolder(MockFolder folder) async {
    if (folder.isSpecial) {
      setState(() {
        _currentPath = [];
        _currentFolders = _combineRealAndTemporaryFolders(_allFolders);
        _selectedFolderPath = '';
        _searchController.clear();
        _isSearching = false;
      });
      return;
    }

    try {
      if (!_isTemporaryFolder(folder)) {
        await _folderService.syncWithDataService();
        final freshFolders = _folderService.folders;
        MockFolder? freshFolder =
            _findFolderInUpdatedData(folder.name, freshFolders);
        if (freshFolder == null) {
          freshFolder = folder;
        }
        folder = freshFolder;
        _allFolders = freshFolders;
      } else {
        // 🔥 FIX: Se è una cartella temporanea, usa sempre la versione più aggiornata
        // dalla lista _localTemporaryFolders per assicurarsi di avere i children aggiornati
        final tempIndex = _localTemporaryFolders.indexWhere(
            (f) => f.name == folder.name && f.level == folder.level);
        if (tempIndex != -1) {
          folder = _localTemporaryFolders[tempIndex];
          print(
              'DEBUG: Navigazione - Usando cartella temporanea aggiornata: ${folder.name} con ${folder.children.length} children');
        }
      }

      List<String> newPath;

      // FIX SEMPLICE: Se clicco su una cartella ROOT, resetto il path
      if (folder.level == 0) {
        // È una cartella root, quindi il path deve essere solo questa cartella
        newPath = [folder.name];
      } else {
        // È una sottocartella, aggiungo al path esistente
        newPath = List.from(_currentPath);
        if (!newPath.contains(folder.name)) {
          newPath.add(folder.name);
        }
      }

      final newSelectedPath = newPath.join(' › ');

      setState(() {
        _currentPath = newPath;
        _currentFolders =
            _combineChildrenWithTemporary(folder.children, newPath);
        _selectedFolderPath = newSelectedPath;
        _searchController.clear();
        _isSearching = false;
      });
    } catch (e) {
      List<String> newPath = List.from(_currentPath);
      if (!newPath.contains(folder.name)) {
        newPath.add(folder.name);
      }
      final newSelectedPath = newPath.join(' › ');

      setState(() {
        _currentPath = newPath;
        _currentFolders =
            _combineChildrenWithTemporary(folder.children, newPath);
        _selectedFolderPath = newSelectedPath;
        _searchController.clear();
        _isSearching = false;
      });
    }
  }

  List<MockFolder> _combineChildrenWithTemporary(
      List<MockFolder> realChildren, List<String> currentPath) {
    final combined = List<MockFolder>.from(realChildren);

    final currentPathString = currentPath.join(' › ');

    for (var tempFolder in _localTemporaryFolders) {
      // 🔥 FIX: Cerca il parent path usando tutte le chiavi che terminano con il nome della cartella
      String? tempParentPath;

      for (var entry in _temporaryFolderPaths.entries) {
        if (entry.key.endsWith(tempFolder.name) &&
            entry.value == currentPathString) {
          tempParentPath = entry.value;
          break;
        }
      }

      if (tempParentPath == currentPathString) {
        final alreadyExists = combined.any((existingFolder) =>
            existingFolder.name == tempFolder.name &&
            existingFolder.level == tempFolder.level);

        if (!alreadyExists) {
          combined.add(tempFolder);
        }
      }
    }

    // Ordina alfabeticamente anche le sottocartelle
    return _sortFolders(combined);
  }

  bool _isTemporaryFolder(MockFolder folder) {
    // 🔥 FIX: Controlla sia il nome che il livello per identificare correttamente cartelle temporanee
    // con lo stesso nome in posizioni diverse
    return _localTemporaryFolders
        .any((temp) => temp.name == folder.name && temp.level == folder.level);
  }

  // Ordina le cartelle alfabeticamente, mantenendo "Tutti" in prima posizione
  List<MockFolder> _sortFolders(List<MockFolder> folders) {
    if (folders.isEmpty) return folders;

    final sortedList = List<MockFolder>.from(folders);

    // Trova la cartella "Tutti" (se esiste)
    MockFolder? tuttiFolder;
    try {
      tuttiFolder = sortedList.firstWhere((f) => f.isSpecial);
      sortedList.remove(tuttiFolder);
    } catch (e) {
      // Non c'è la cartella "Tutti", continua normalmente
    }

    // Ordina le altre cartelle alfabeticamente (case-insensitive)
    sortedList
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Rimetti "Tutti" in prima posizione se esiste
    if (tuttiFolder != null) {
      sortedList.insert(0, tuttiFolder);
    }

    return sortedList;
  }

  void _navigateBack() {
    if (_currentPath.isEmpty) return;

    setState(() {
      _currentPath.removeLast();

      if (_currentPath.isEmpty) {
        // Quando torniamo alla homepage, gestisci il cleanup correttamente
        if (_selectedFolderPath == null || _selectedFolderPath!.isEmpty) {
          // Nessuna selezione: pulisci tutte le cartelle temporanee
          _cleanupAllTemporaryFolders();
          _currentFolders = _sortFolders(_allFolders);
          _selectedFolderPath = '';
        } else {
          // C'è una selezione: pulisci solo le cartelle abbandonate
          _cleanupAbandonedTemporaryFolders();
          _currentFolders = _combineRealAndTemporaryFolders(_allFolders);
        }
      } else {
        final parentFolder = _findFolderByPath(_currentPath);
        if (parentFolder != null) {
          _currentFolders = _combineChildrenWithTemporary(
              parentFolder.children, _currentPath);
          _selectedFolderPath = _currentPath.join(' › ');
        } else {
          _currentPath = [];
          _cleanupAllTemporaryFolders();
          _currentFolders = _sortFolders(_allFolders);
          _selectedFolderPath = '';
        }
      }

      _searchController.clear();
      _isSearching = false;
    });
  }

  void _selectFolder(MockFolder folder) {
    final folderPath = _buildFolderPath(folder);

    setState(() {
      _selectedFolderPath = folderPath;
    });
  }

  void _selectFolderAndClose(String folderPath) {
    widget.onFolderSelected(folderPath);
    Navigator.pop(context);
  }

  String _buildFolderPath(MockFolder folder) {
    if (folder.isSpecial) {
      return '';
    }

    if (_isTemporaryFolder(folder)) {
      // 🔥 FIX: Cerca la cartella usando il percorso completo
      for (var entry in _temporaryFolderPaths.entries) {
        final key = entry.key;
        final parentPath = entry.value;

        // Verifica se questa entry corrisponde a questa cartella
        if (key.endsWith(folder.name)) {
          final expectedFullPath =
              parentPath.isEmpty ? folder.name : '$parentPath › ${folder.name}';
          if (key == expectedFullPath) {
            return expectedFullPath;
          }
        }
      }
    }

    List<String> pathParts = [];
    MockFolder? current = folder;

    while (current != null && !current.isSpecial) {
      pathParts.insert(0, current.name);
      current = current.parent;
    }

    final finalPath = pathParts.join(' › ');
    return finalPath;
  }

  MockFolder? _findFolderInUpdatedData(
      String folderName, List<MockFolder> freshFolders) {
    if (_currentPath.isEmpty) {
      try {
        return freshFolders.firstWhere(
          (f) => !f.isSpecial && f.name == folderName,
        );
      } catch (e) {
        return null;
      }
    }

    MockFolder? current;
    try {
      current = freshFolders.firstWhere(
        (f) => !f.isSpecial && f.name == _currentPath.first,
      );
    } catch (e) {
      return null;
    }

    for (int i = 1; i < _currentPath.length; i++) {
      if (current == null) {
        return null;
      }

      try {
        current = current.children.firstWhere(
          (child) => child.name == _currentPath[i],
        );
      } catch (e) {
        return null;
      }
    }

    if (current != null) {
      try {
        return current.children.firstWhere(
          (child) => child.name == folderName,
        );
      } catch (e) {
        return null;
      }
    }

    return null;
  }

  MockFolder? _findFolderByPathSafe(
      List<String> pathParts, List<MockFolder> foldersList) {
    if (pathParts.isEmpty) return null;

    MockFolder? current;
    try {
      current = foldersList.firstWhere(
        (f) => !f.isSpecial && f.name == pathParts.first,
      );
    } catch (e) {
      return null;
    }

    for (int i = 1; i < pathParts.length; i++) {
      if (current == null) {
        return null;
      }

      try {
        current = current.children.firstWhere(
          (child) => child.name == pathParts[i],
        );
      } catch (e) {
        return null;
      }
    }

    return current;
  }

  MockFolder? _findFolderByPath(List<String> pathParts) {
    if (pathParts.isEmpty) return null;

    MockFolder? current;
    try {
      current = _allFolders.firstWhere(
        (f) => !f.isSpecial && f.name == pathParts.first,
      );
    } catch (e) {
      try {
        current = _localTemporaryFolders.firstWhere(
          (f) => f.name == pathParts.first,
        );
      } catch (e2) {
        return null;
      }
    }

    // 🔥 FIX: Naviga attraverso i livelli successivi cercando anche nelle cartelle temporanee
    for (int i = 1; i < pathParts.length; i++) {
      if (current == null) {
        return null;
      }

      try {
        // Cerca prima nei children della cartella corrente
        current = current.children.firstWhere(
          (child) => child.name == pathParts[i],
        );
      } catch (e) {
        // 🔥 FIX: Se non trovato nei children, cerca nelle cartelle temporanee
        // che potrebbero essere state aggiunte di recente
        try {
          final pathSoFar = pathParts.sublist(0, i).join(' › ');
          final expectedFullPath = _getTempFolderKey(pathParts[i], pathSoFar);

          current = _localTemporaryFolders.firstWhere(
            (f) {
              // Controlla se il percorso completo di questa cartella corrisponde
              return _temporaryFolderPaths[expectedFullPath] == pathSoFar;
            },
          );
        } catch (e2) {
          return null;
        }
      }
    }

    return current;
  }

  bool _isAtMaxLevel() {
    if (_currentPath.isEmpty) {
      return false;
    }

    final currentFolder = _findFolderByPath(_currentPath);
    if (currentFolder == null) {
      return false;
    }

    final isAtMax =
        _accessService.validateSubfolderCreation(currentFolder) != null;

    if (isAtMax) {
      print(
          'DEBUG: Raggiunto livello massimo. Cartella corrente: ${currentFolder.name}, Livello: ${currentFolder.level}');
    }

    return isAtMax;
  }

  void _showDebugMessage(String message) {}

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: _mainBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            _buildMiniHeader(),
            Expanded(
              child: _buildMiniHomeContent(),
            ),
            _buildBreadcrumbSection(),
            _buildSelectionFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _mainBackgroundColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border(
          bottom: BorderSide(
            color: widget.isDarkTheme
                ? Colors.grey.shade800
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark, color: _iconColor, size: 20),
              SizedBox(width: 8),
              Image.asset(
                'assets/icon/SaveIn!.png',
                height: 48,
                fit: BoxFit.contain,
              ),
              Spacer(),
              IconButton(
                onPressed: () {
                  _handleCancelWithCleanup();
                },
                icon: Icon(Icons.close, color: _iconColor),
                iconSize: 20,
              ),
            ],
          ),
          SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: Color.fromARGB(255, 66, 66, 66)),
              decoration: InputDecoration(
                hintText: 'Cerca cartelle...',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey.shade600),
                        onPressed: () {
                          _searchController.clear();
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : Icon(Icons.search, color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniHomeContent() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'Caricamento cartelle...',
              style: TextStyle(color: _textColor),
            ),
          ],
        ),
      );
    }

    if (_currentPath.isNotEmpty && _currentFolders.isEmpty) {
      return _buildEmptySubfolderState();
    }

    return Padding(
      padding: EdgeInsets.all(16),
      child: _currentFolders.isEmpty
          ? _buildEmptyState()
          : GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: _currentFolders.length,
              itemBuilder: (context, index) {
                return _buildMiniHomeFolderCard(_currentFolders[index]);
              },
            ),
    );
  }

  Widget _buildEmptySubfolderState() {
    final currentFolderName = _currentPath.last;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: Icon(
              Icons.folder_outlined,
              size: 48,
              color: Colors.blue,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Cartella "$currentFolderName"',
            style: TextStyle(
              color: _textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '✅ SELEZIONATA COME DESTINAZIONE',
              style: TextStyle(
                color: Colors.green,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Non contiene sottocartelle',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Usa il pulsante in basso per creare una sottocartella',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniHomeFolderCard(MockFolder folder) {
    final folderPath = _buildFolderPath(folder);
    final isSelected = _selectedFolderPath == folderPath;
    final hasChildren = folder.children.isNotEmpty;
    final isTemporary = _isTemporaryFolder(folder);

    return GestureDetector(
      onTap: () async {
        if (folder.isSpecial) {
          setState(() {
            _selectedFolderPath = '';
          });
        } else {
          await _navigateToFolder(folder);
        }
      },
      onLongPress: () {
        if (folder.isSpecial) {
          setState(() {
            _selectedFolderPath = '';
          });
        } else {
          _selectFolder(folder);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: folder.color,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: Colors.green, width: 3) : null,
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
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      folder.isSpecial
                          ? Icons.bookmark
                          : (hasChildren
                              ? Icons.folder
                              : Icons.folder_outlined),
                      color: Colors.black87,
                      size: 20,
                    ),
                  ),
                  Spacer(),
                  Text(
                    folder.name,
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    folder.count,
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            if (hasChildren && !folder.isSpecial)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off,
            size: 48,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            _isSearching ? 'Nessun risultato' : 'Nessuna cartella',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _isSearching
                ? 'Prova con altri termini di ricerca'
                : 'Crea la tua prima cartella',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbSection() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isDarkTheme
            ? Colors.grey[800]?.withOpacity(0.5)
            : Colors.grey[100]?.withOpacity(0.7),
        border: Border(
          top: BorderSide(
            color: widget.isDarkTheme
                ? Colors.grey.shade800
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_open,
            color: Colors.blue,
            size: 16,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 28,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: _buildCompactBreadcrumb(),
              ),
            ),
          ),
          SizedBox(width: 12),
          _buildCompactBackButton(),
        ],
      ),
    );
  }

  Widget _buildCompactBreadcrumb() {
    if (_currentPath.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home, color: Colors.green, size: 10),
            SizedBox(width: 3),
            Text(
              'Home',
              style: TextStyle(
                color: Colors.green,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    final pathComponents = List<String>.from(_currentPath);

    if (pathComponents.length > 2) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.home, color: _subtitleColor, size: 8),
                SizedBox(width: 2),
                Text('Home',
                    style: TextStyle(color: _subtitleColor, fontSize: 9)),
              ],
            ),
          ),
          Icon(Icons.keyboard_arrow_right, color: _subtitleColor, size: 10),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text('...',
                style: TextStyle(color: _subtitleColor, fontSize: 9)),
          ),
          Icon(Icons.keyboard_arrow_right, color: _subtitleColor, size: 10),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder, color: Colors.blue, size: 10),
                SizedBox(width: 3),
                Text(
                  pathComponents.last.length > 8
                      ? '${pathComponents.last.substring(0, 8)}...'
                      : pathComponents.last,
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.home, color: _subtitleColor, size: 8),
              SizedBox(width: 2),
              Text('Home',
                  style: TextStyle(color: _subtitleColor, fontSize: 9)),
            ],
          ),
        ),
        ...pathComponents.asMap().entries.map((entry) {
          final index = entry.key;
          final component = entry.value;
          final isLast = index == pathComponents.length - 1;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_right, color: _subtitleColor, size: 10),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: isLast
                      ? Colors.blue.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      isLast ? Border.all(color: Colors.blue, width: 1) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder,
                      color: isLast ? Colors.blue : _subtitleColor,
                      size: 10,
                    ),
                    SizedBox(width: 3),
                    Text(
                      component.length > 8
                          ? '${component.substring(0, 8)}...'
                          : component,
                      style: TextStyle(
                        color: isLast ? Colors.blue : _textColor,
                        fontSize: 10,
                        fontWeight:
                            isLast ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ],
    );
  }

  Widget _buildCompactBackButton() {
    final canGoBack = _currentPath.isNotEmpty;

    return Material(
      color: canGoBack
          ? Colors.orange.withOpacity(0.15)
          : Colors.grey.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: canGoBack ? _navigateBack : null,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back,
                color: canGoBack ? Colors.orange : Colors.grey,
                size: 14,
              ),
              SizedBox(width: 3),
              Text(
                'Indietro',
                style: TextStyle(
                  color: canGoBack ? Colors.orange : Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionFooter() {
    final isAtMaxLevel = _isAtMaxLevel();
    final currentLevelText = _currentPath.isEmpty
        ? "Livello principale"
        : "Livello ${_currentPath.length + 1}/5";

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        border: Border(
          top: BorderSide(
            color: widget.isDarkTheme
                ? Colors.grey.shade800
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isAtMaxLevel
                  ? null
                  : () {
                      if (_isAtMaxLevel()) {
                        print(
                            'DEBUG: ⛔ PULSANTE - Tentativo bloccato, siamo al limite!');
                        _showValidationError('Limite di 5 livelli raggunto');
                        return;
                      }
                      print(
                          'DEBUG: ✅ PULSANTE - Chiamando _showCreateFolderDialog');
                      _showCreateFolderDialog();
                    },
              icon: Icon(
                Icons.create_new_folder,
                size: 20,
                color: isAtMaxLevel ? Colors.grey.shade600 : Colors.white,
              ),
              label: Text(
                isAtMaxLevel
                    ? 'Limite 5 livelli raggiunto'
                    : 'Crea Nuova Cartella',
                style: TextStyle(
                  fontSize: isAtMaxLevel ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: isAtMaxLevel ? Colors.grey.shade600 : Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isAtMaxLevel ? Colors.grey.shade400 : Colors.blue,
                foregroundColor:
                    isAtMaxLevel ? Colors.grey.shade600 : Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                splashFactory: isAtMaxLevel
                    ? NoSplash.splashFactory
                    : InkRipple.splashFactory,
              ),
            ),
          ),
          if (isAtMaxLevel) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Hai raggiunto il $currentLevelText',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _handleCancelWithCleanup,
                  child: Text(
                    'Annulla',
                    style: TextStyle(fontSize: 15),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _textColor,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    _transferTemporaryFoldersToParent();
                    widget.onFolderSelected(_selectedFolderPath ?? '');
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Conferma Selezione',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog() {
    final TextEditingController nameController = TextEditingController();
    final currentPathString = _currentPath.join(' › ');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.create_new_folder, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nuova Cartella',
                    style: TextStyle(
                        color: _textColor, fontWeight: FontWeight.bold),
                  ),
                  if (currentPathString.isNotEmpty)
                    Text(
                      'in: $currentPathString',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentPathString.isEmpty
                  ? 'Crea una nuova cartella principale.'
                  : 'Crea una sottocartella in "$currentPathString".',
              style: TextStyle(color: _textColor, fontSize: 14),
            ),
            SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Nome cartella',
                hintText: 'es. Progetti, Archivio, Ricette...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor:
                    widget.isDarkTheme ? Colors.grey[800] : Colors.grey[50],
              ),
              autofocus: true,
              style: TextStyle(color: _textColor),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (value) async {
                final text = nameController.text.trim();
                if (text.isNotEmpty) {
                  await _createTemporaryFolder(text, closeDialog: true);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: _textColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              print('DEBUG: ========== PULSANTE CREA PREMUTO ==========');
              final text = nameController.text.trim();
              print('DEBUG: Testo inserito: "$text"');
              print('DEBUG: Testo vuoto: ${text.isEmpty}');

              if (text.isEmpty) {
                print('DEBUG: Testo vuoto, mostrando errore');
                _showValidationError('Inserisci un nome cartella');
                return;
              }

              print('DEBUG: Chiamando _createTemporaryFolder con: "$text"');
              await _createTemporaryFolder(text, closeDialog: true);
              print('DEBUG: _createTemporaryFolder completato');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text('Crea'),
          ),
        ],
      ),
    );
  }

  Future<void> _createTemporaryFolder(String folderName,
      {bool closeDialog = false}) async {
    try {
      print('DEBUG: ========== TENTATIVO CREAZIONE CARTELLA ==========');
      print('DEBUG: Nome richiesto: "$folderName"');
      print('DEBUG: Path corrente: $_currentPath');
      print('DEBUG: Livello corrente: ${_currentPath.length}');

      _showDebugMessage('Path: $_currentPath (length: ${_currentPath.length})');

      if (_isAtMaxLevel()) {
        print('DEBUG: ⛔ BLOCCATO - Limite livelli raggiunto');
        _showDebugMessage('BLOCCATO: Limite livelli raggiunto');
        _showValidationError(
            'Raggiunto il limite massimo di 5 livelli totali (livelli 0-4)');
        return;
      }

      // 🔥 FIX: Trova il parent folder per validazione corretta
      MockFolder? parentFolder;
      if (_currentPath.isNotEmpty) {
        parentFolder = _findFolderByPath(_currentPath);
      }

      final validationError =
          _folderService.validateFolderName(folderName, parent: parentFolder);
      if (validationError != null) {
        print('DEBUG: ⛔ BLOCCATO - Nome non valido: $validationError');
        _showValidationError(validationError);
        return;
      }

      final currentPathString = _currentPath.join(' › ');
      final fullPath = currentPathString.isEmpty
          ? folderName
          : '$currentPathString › $folderName';

      // 🔥 FIX: Controlla duplicati usando il percorso completo come chiave
      if (_temporaryFolderPaths.containsKey(fullPath)) {
        print('DEBUG: ⛔ BLOCCATO - Cartella duplicata (chiave: $fullPath)');
        _showValidationError(
            'Cartella "$folderName" esiste già in questa posizione');
        return;
      }

      // 🔥 FIX: Calcola il livello basandosi sul parent già trovato
      int newLevel = 0;

      if (parentFolder != null) {
        _showDebugMessage(
            '✅ Parent trovato: ${parentFolder.name} (liv ${parentFolder.level})');
        newLevel = parentFolder.level + 1;
        print(
            'DEBUG: Parent trovata: ${parentFolder.name} (livello ${parentFolder.level})');
        print('DEBUG: Nuovo livello calcolato: $newLevel');

        if (newLevel > AppConstants.maxFolderLevels) {
          print(
              'DEBUG: ⛔ BLOCCATO - Doppio controllo limite fallito (newLevel: $newLevel)');
          _showDebugMessage(
              'BLOCCATO: newLevel $newLevel > ${AppConstants.maxFolderLevels}');
          _showValidationError(
              'Raggiunto il limite massimo di 5 livelli totali (livelli 0-4)');
          return;
        }
      }

      print('DEBUG: ✅ VALIDAZIONI SUPERATE - Procedendo con creazione');
      _showDebugMessage('✅ VALIDAZIONI OK - Creando cartella liv $newLevel');

      final newFolder = MockFolder(
        name: FolderManagement.capitalizeFirst(folderName),
        count: 'Temporanea',
        color: FolderManagement.getRandomColor(),
        level: newLevel,
        parent: parentFolder,
        children: [],
      );

      print(
          'DEBUG: Cartella creata in memoria: ${newFolder.name} (livello ${newFolder.level})');

      setState(() {
        _localTemporaryFolders.add(newFolder);
        // 🔥 FIX: Usa il percorso completo come chiave invece di solo il nome
        final fullPath = _getTempFolderKey(newFolder.name, currentPathString);
        _temporaryFolderPaths[fullPath] = currentPathString;

        if (parentFolder != null) {
          // 🔥 FIX: Trova il parent nelle cartelle temporanee per aggiornarlo
          final parentIndex = _localTemporaryFolders.indexWhere((f) =>
              f.name == parentFolder!.name && f.level == parentFolder!.level);

          MockFolder updatedParentFolder = parentFolder;

          if (parentIndex != -1) {
            // Aggiorna i children del parent nella lista temporanea
            _localTemporaryFolders[parentIndex].children =
                List.from(_localTemporaryFolders[parentIndex].children)
                  ..add(newFolder);

            // 🔥 FIX: Usa il parent aggiornato per le operazioni successive
            updatedParentFolder = _localTemporaryFolders[parentIndex];

            _showDebugMessage(
                '✅ Parent-child link aggiornato: ${parentFolder!.name} -> ${newFolder.name}');
            print(
                'DEBUG: ✅ Aggiornato parent-child: ${parentFolder!.name}.children ora include ${newFolder.name}');
          } else {
            // 🔥 FIX: Se il parent non è nelle temporary folders, aggiungi comunque il child
            // Questo può succedere se il parent è una cartella reale dal database
            _showDebugMessage(
                '⚠️ Parent non temporaneo, aggiungendo child direttamente');
            print(
                'DEBUG: ⚠️ Parent non trovato in _localTemporaryFolders, probabilmente è una cartella reale');
          }

          // 🔥 FIX: Usa il parent aggiornato per combinare i children
          _currentFolders = _combineChildrenWithTemporary(
              updatedParentFolder.children, _currentPath);
        } else {
          // Combina e ordina le cartelle root
          _currentFolders = _combineRealAndTemporaryFolders(_allFolders);
        }

        _selectedFolderPath = fullPath;
      });

      print(
          'DEBUG: Stato aggiornato - cartella aggiunta alle liste temporanee');

      _showDebugMessage('✅ SUCCESS: ${folderName} creata (liv $newLevel)');

      // Mostra messaggio di successo
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cartella "$folderName" creata con successo!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      print(
          'DEBUG: ✅ SUCCESSO - Cartella temporanea creata: $folderName (livello $newLevel)');

      // Chiudi il dialog se richiesto
      if (closeDialog) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('ERRORE: Creazione cartella temporanea fallita: $e');
      print('ERRORE: Stack trace completo per debug');
      _showDebugMessage('❌ ERRORE: ${e.toString()}');
      _showCreationError(folderName, e.toString());

      setState(() {
        _localTemporaryFolders.removeWhere((f) => f.name == folderName);
        // 🔥 FIX: Rimuovi usando il percorso completo
        final currentPathString = _currentPath.join(' › ');
        final fullPath = _getTempFolderKey(folderName, currentPathString);
        _temporaryFolderPaths.remove(fullPath);
      });
    }
  }

  void _handleCancelWithCleanup() {
    _cleanupAllTemporaryFolders();
    Navigator.pop(context);
  }

  void _cleanupAllTemporaryFolders() {
    if (_localTemporaryFolders.isNotEmpty) {
      _localTemporaryFolders.clear();
      _temporaryFolderPaths.clear();
    }
  }

  void _cleanupAbandonedTemporaryFolders() {
    if (_localTemporaryFolders.isEmpty) return;

    if (_selectedFolderPath == null || _selectedFolderPath!.isEmpty) {
      _cleanupAllTemporaryFolders();
      return;
    }

    final selectedPathParts = _selectedFolderPath!.split(' › ');
    final foldersToKeep = selectedPathParts.toSet();

    final foldersToRemove = <MockFolder>[];
    final pathsToRemove = <String>[];

    for (var tempFolder in _localTemporaryFolders) {
      if (!foldersToKeep.contains(tempFolder.name)) {
        foldersToRemove.add(tempFolder);
        pathsToRemove.add(tempFolder.name);
      }
    }

    if (foldersToRemove.isNotEmpty) {
      for (var folder in foldersToRemove) {
        _localTemporaryFolders.remove(folder);
      }

      for (var pathKey in pathsToRemove) {
        _temporaryFolderPaths.remove(pathKey);
      }
    }
  }

  void _transferTemporaryFoldersToParent() {
    if (_localTemporaryFolders.isNotEmpty &&
        widget.onTemporaryFolderCreated != null) {
      if (_selectedFolderPath == null || _selectedFolderPath!.isEmpty) {
        return;
      }

      final selectedPathParts = _selectedFolderPath!.split(' › ');
      final foldersToTransfer = <String>{};

      String currentPath = '';
      for (int i = 0; i < selectedPathParts.length; i++) {
        final folderName = selectedPathParts[i];
        foldersToTransfer.add(folderName);

        if (i == 0) {
          currentPath = folderName;
        } else {
          currentPath = '$currentPath › $folderName';
        }
      }

      for (var tempFolder in _localTemporaryFolders) {
        if (foldersToTransfer.contains(tempFolder.name)) {
          // 🔥 FIX: Trova il parent path usando tutte le chiavi nella map
          String? parentPath;

          for (var entry in _temporaryFolderPaths.entries) {
            if (entry.key.endsWith(tempFolder.name)) {
              parentPath = entry.value;
              break;
            }
          }

          if (parentPath != null) {
            widget.onTemporaryFolderCreated!(tempFolder.name, parentPath);
          }
        }
      }
    }
  }

  void _showValidationError(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showCreationError(String folderName, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Errore creazione "$folderName": $error'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }
}
