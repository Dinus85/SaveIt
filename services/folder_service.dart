import 'package:flutter/material.dart';
import '../models/folder.dart';
import '../utils/folder_management.dart';

// Classe per rappresentare un post mockato
class MockPost {
  final String id;
  final String title;
  final String url;
  final String description;
  final DateTime savedDate;
  final MockFolder? sourceFolder; // Da quale cartella proviene
  final List<String> tags;

  MockPost({
    required this.id,
    required this.title,
    required this.url,
    required this.description,
    required this.savedDate,
    this.sourceFolder,
    this.tags = const [],
  });
}

// Service per la gestione della logica di business delle cartelle
class FolderService {
  List<MockFolder> _folders = [];
  List<MockPost> _allPosts = []; // Tutti i post salvati
  
  // Getter per le cartelle
  List<MockFolder> get folders => _folders;
  
  // Getter per tutti i post
  List<MockPost> get allPosts => _allPosts;

  // Inizializza le cartelle con dati di esempio
  void initializeFolders() {
    _folders = [
      MockFolder(name: 'Tutti', count: '0 Post', color: Colors.purple.shade200, level: 0, isSpecial: true),
      MockFolder(name: 'Ricette', count: 'Vuota', color: Colors.orange.shade200, level: 0),
      MockFolder(name: 'Viaggi', count: 'Vuota', color: Colors.orange.shade100, level: 0),
      MockFolder(name: 'Progetti', count: 'Vuota', color: Colors.orange.shade200, level: 0),
      MockFolder(name: 'Design', count: 'Vuota', color: Colors.orange.shade200, level: 0),
    ];
    
    setupExampleHierarchy();
    _createMockPosts(); // Crea i post di esempio
    updateTuttiCount();
  }

  // Crea la gerarchia di esempio
  void setupExampleHierarchy() {
    // Trova la cartella "Ricette" e aggiungi alcune sottocartelle
    final ricetteFolder = _folders.firstWhere((f) => f.name == 'Ricette', orElse: () => _folders[1]);
    
    // Crea "Primi"
    final primiFolder = MockFolder(
      name: 'Primi',
      count: 'Vuota',
      color: Colors.orange.shade300,
      level: 1,
      parent: ricetteFolder,
    );
    
    // Crea "Mare" sotto "Primi"
    final mareFolder = MockFolder(
      name: 'Mare',
      count: 'Vuota', 
      color: Colors.blue.shade200,
      level: 2,
      parent: primiFolder,
    );
    
    // Crea "Este" sotto "Mare"
    final esteFolder = MockFolder(
      name: 'Este',
      count: 'Vuota',
      color: Colors.cyan.shade200,
      level: 3,
      parent: mareFolder,
    );
    
    // Costruisci la gerarchia
    mareFolder.children.add(esteFolder);
    primiFolder.children.add(mareFolder);
    ricetteFolder.children.add(primiFolder);
  }

  // Crea post di esempio per la demo
  void _createMockPosts() {
    final ricetteFolder = _folders.firstWhere((f) => f.name == 'Ricette');
    final viaggiFolder = _folders.firstWhere((f) => f.name == 'Viaggi');
    final progettiFolder = _folders.firstWhere((f) => f.name == 'Progetti');
    
    // Trova le sottocartelle per i post più specifici
    final primiFolder = ricetteFolder.children.isNotEmpty ? ricetteFolder.children[0] : ricetteFolder;
    final mareFolder = primiFolder.children.isNotEmpty ? primiFolder.children[0] : primiFolder;
    final esteFolder = mareFolder.children.isNotEmpty ? mareFolder.children[0] : mareFolder;

    _allPosts = [
      // Post in Ricette > Primi
      MockPost(
        id: '1',
        title: 'Spaghetti alle Vongole - Ricetta Originale',
        url: 'https://www.giallozafferano.it/ricette/Spaghetti-alle-vongole.html',
        description: 'La ricetta classica degli spaghetti alle vongole napoletana, con ingredienti semplici e genuini.',
        savedDate: DateTime.now().subtract(Duration(days: 2)),
        sourceFolder: primiFolder,
        tags: ['pasta', 'pesce', 'napoletana'],
      ),
      
      // Post in Ricette > Primi > Mare
      MockPost(
        id: '2',
        title: 'Risotto ai Frutti di Mare',
        url: 'https://www.cookaround.com/ricetta/Risotto-ai-frutti-di-mare.html',
        description: 'Un cremoso risotto con gamberi, cozze e vongole per gli amanti del pesce.',
        savedDate: DateTime.now().subtract(Duration(days: 5)),
        sourceFolder: mareFolder,
        tags: ['risotto', 'frutti di mare', 'primo'],
      ),
      
      MockPost(
        id: '3',
        title: 'Linguine allo Scoglio',
        url: 'https://ricette.donnamoderna.com/linguine-allo-scoglio',
        description: 'Pasta con mix di frutti di mare freschi e pomodorini.',
        savedDate: DateTime.now().subtract(Duration(days: 8)),
        sourceFolder: mareFolder,
        tags: ['linguine', 'scoglio', 'pasta'],
      ),
      
      // Post in Ricette > Primi > Mare > Este  
      MockPost(
        id: '4',
        title: 'Specialità Marinare di Este',
        url: 'https://www.venetoinfo.it/cucina-este-pesce',
        description: 'Piatti di pesce tipici della tradizione estense.',
        savedDate: DateTime.now().subtract(Duration(days: 1)),
        sourceFolder: esteFolder,
        tags: ['este', 'tradizione', 'veneto'],
      ),
      
      // Post in Viaggi
      MockPost(
        id: '5',
        title: 'Guida Completa a Venezia',
        url: 'https://www.veneziaunica.it/it/content/guida-venezia',
        description: 'Tutto quello che devi sapere per visitare Venezia: attrazioni, trasporti e consigli.',
        savedDate: DateTime.now().subtract(Duration(days: 10)),
        sourceFolder: viaggiFolder,
        tags: ['venezia', 'guida', 'turismo'],
      ),
      
      MockPost(
        id: '6',
        title: 'Le Migliori Spiagge del Veneto',
        url: 'https://www.veneto.info/spiagge-veneto',
        description: 'Scopri le spiagge più belle della costa veneta, da Jesolo a Bibione.',
        savedDate: DateTime.now().subtract(Duration(days: 15)),
        sourceFolder: viaggiFolder,
        tags: ['spiagge', 'veneto', 'estate'],
      ),
      
      MockPost(
        id: '7',
        title: 'Itinerario nelle Ville Palladiane',
        url: 'https://www.villepalladiane.it/itinerari',
        description: 'Un percorso attraverso le magnifiche ville progettate da Andrea Palladio.',
        savedDate: DateTime.now().subtract(Duration(days: 7)),
        sourceFolder: viaggiFolder,
        tags: ['palladio', 'ville', 'architettura'],
      ),
      
      // Post in Progetti
      MockPost(
        id: '8',
        title: 'Flutter: Guida Completa al Framework',
        url: 'https://flutter.dev/docs',
        description: 'Documentazione ufficiale di Flutter per sviluppare app multipiattaforma.',
        savedDate: DateTime.now().subtract(Duration(days: 3)),
        sourceFolder: progettiFolder,
        tags: ['flutter', 'development', 'mobile'],
      ),
    ];
  }

  // Aggiorna il conteggio della cartella "Tutti" e di tutte le cartelle
  void updateTuttiCount() {
    // Aggiorna la cartella "Tutti" - SOLO post, nessuna cartella
    final tuttiFolder = _folders.firstWhere((f) => f.isSpecial);
    final totalPosts = _allPosts.length;
    tuttiFolder.count = totalPosts > 0 ? '$totalPosts Post' : 'Vuota';
    
    // Aggiorna i conteggi di tutte le altre cartelle
    _updateAllFolderCounts();
  }

  // Aggiorna i conteggi di tutte le cartelle (tranne "Tutti")
  void _updateAllFolderCounts() {
    for (var folder in _folders) {
      if (!folder.isSpecial) {
        _updateFolderCount(folder);
      }
    }
  }

  // Aggiorna il conteggio di una singola cartella
  void _updateFolderCount(MockFolder folder) {
    final subfolderCount = folder.children.length;
    final totalPosts = _getPostCountForFolderAndChildren(folder);
    
    if (subfolderCount == 0 && totalPosts == 0) {
      folder.count = 'Vuota';
    } else if (subfolderCount == 0) {
      folder.count = '$totalPosts Post';
    } else if (totalPosts == 0) {
      folder.count = '$subfolderCount ${subfolderCount == 1 ? 'cartella' : 'cartelle'}';
    } else {
      folder.count = '$subfolderCount ${subfolderCount == 1 ? 'cartella' : 'cartelle'} • $totalPosts Post';
    }
    
    // Aggiorna ricorsivamente le sottocartelle
    for (var child in folder.children) {
      _updateFolderCount(child);
    }
  }

  // Conta i post in una cartella e in tutte le sue sottocartelle
  int _getPostCountForFolderAndChildren(MockFolder folder) {
    int count = _allPosts.where((post) => post.sourceFolder == folder).length;
    
    for (var child in folder.children) {
      count += _getPostCountForFolderAndChildren(child);
    }
    
    return count;
  }

  // Ottieni tutti i post (per la cartella "Tutti")
  List<MockPost> getAllPosts() {
    return List.from(_allPosts)..sort((a, b) => b.savedDate.compareTo(a.savedDate));
  }

  // Ottieni i post di una cartella specifica
  List<MockPost> getPostsForFolder(MockFolder folder) {
    if (folder.isSpecial) {
      return getAllPosts(); // La cartella "Tutti" mostra tutti i post
    }
    
    // Per le altre cartelle, mostra i post della cartella stessa + delle sottocartelle
    List<MockPost> posts = [];
    
    void collectPosts(MockFolder currentFolder) {
      posts.addAll(_allPosts.where((post) => post.sourceFolder == currentFolder));
      for (var child in currentFolder.children) {
        collectPosts(child);
      }
    }
    
    collectPosts(folder);
    
    return posts..sort((a, b) => b.savedDate.compareTo(a.savedDate));
  }

  // Crea una nuova cartella
  void createFolder(String name) {
    final newFolder = MockFolder(
      name: FolderManagement.capitalizeFirst(name),
      count: 'Vuota',
      color: FolderManagement.getRandomColor(),
      level: 0,
      parent: null,
    );
    _folders.add(newFolder);
    updateTuttiCount();
  }

  // Crea una nuova sottocartella
  void createSubfolder(MockFolder parentFolder, String name) {
    if (!parentFolder.canHaveSubfolders) return;
    
    final newSubfolder = MockFolder(
      name: FolderManagement.capitalizeFirst(name),
      count: 'Vuota',
      color: FolderManagement.getRandomColor(),
      level: parentFolder.level + 1,
      parent: parentFolder,
    );
    parentFolder.children.add(newSubfolder);
    updateTuttiCount();
  }

  // Rinomina una cartella
  void renameFolder(MockFolder folder, String newName) {
    folder.name = FolderManagement.capitalizeFirst(newName);
    updateTuttiCount();
  }

  // Elimina una cartella
  void deleteFolder(MockFolder folder) {
    if (folder.isSpecial) return;
    
    FolderManagement.removeFolderFromHierarchy(folder, _folders);
    updateTuttiCount();
  }

  // Sposta una cartella
  void moveFolder(MockFolder folderToMove, MockFolder? destination) {
    if (folderToMove.isSpecial) return;
    if (!FolderManagement.canMoveFolder(folderToMove, destination)) return;
    
    // Rimuovi la cartella dalla posizione attuale
    if (folderToMove.parent != null) {
      folderToMove.parent!.children.remove(folderToMove);
    } else {
      _folders.remove(folderToMove);
    }
    
    // Aggiorna il parent e il livello
    folderToMove.parent = destination;
    if (destination != null) {
      folderToMove.level = destination.level + 1;
      destination.children.add(folderToMove);
    } else {
      folderToMove.level = 0;
      _folders.add(folderToMove);
    }
    
    // Aggiorna ricorsivamente i livelli delle sottocartelle
    FolderManagement.updateSubfolderLevels(folderToMove);
    updateTuttiCount();
  }

  // Cerca cartelle
  List<MockFolder> searchFolders(String query) {
    return FolderManagement.searchFolders(query, _folders);
  }

  // Cerca post
  List<MockPost> searchPosts(String query) {
    return _allPosts.where((post) => 
      post.title.toLowerCase().contains(query.toLowerCase()) ||
      post.description.toLowerCase().contains(query.toLowerCase()) ||
      post.tags.any((tag) => tag.toLowerCase().contains(query.toLowerCase()))
    ).toList()..sort((a, b) => b.savedDate.compareTo(a.savedDate));
  }

  // Calcola statistiche per l'account
  Map<String, int> getAccountStats() {
    int totalFolders = _folders.length;
    
    void countSubfolders(MockFolder folder) {
      totalFolders += folder.children.length;
      for (var child in folder.children) {
        countSubfolders(child);
      }
    }
    
    for (var folder in _folders) {
      countSubfolders(folder);
    }
    
    return {
      'totalPosts': _allPosts.length,
      'totalFolders': totalFolders,
    };
  }

  // Verifica se una cartella può avere sottocartelle
  bool canCreateSubfolder(MockFolder folder) {
    return folder.canHaveSubfolders;
  }

  // Ottiene il breadcrumb di una cartella
  String getFolderBreadcrumb(MockFolder folder) {
    return FolderManagement.buildBreadcrumb(folder);
  }

  // Ottiene tutte le cartelle disponibili come destinazione per lo spostamento
  List<MockFolder> getAvailableDestinations(MockFolder folderToMove) {
    List<MockFolder> destinations = [];
    
    for (var folder in _folders) {
      if (folder.isSpecial || folder == folderToMove) continue;
      if (FolderManagement.isDescendantOf(folder, folderToMove)) continue;
      if (FolderManagement.canMoveFolder(folderToMove, folder)) {
        destinations.add(folder);
      }
    }
    
    return destinations;
  }

  // Clona una cartella per i risultati di ricerca
  MockFolder cloneFolderForSearch(MockFolder original, String displayPath) {
    return MockFolder(
      name: displayPath,
      count: original.count,
      color: original.color,
      level: original.level,
      originalFolder: original,
    );
  }

  // Trova una cartella per ID (simulato con confronto di oggetti)
  MockFolder? findFolderById(MockFolder targetFolder) {
    return FolderManagement.findFolderInHierarchy(targetFolder, _folders);
  }

  // Simula l'aggiunta di un nuovo post
  void addMockPost(String title, String url, MockFolder? targetFolder) {
    final newPost = MockPost(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      url: url,
      description: 'Post aggiunto dall\'utente',
      savedDate: DateTime.now(),
      sourceFolder: targetFolder,
      tags: ['demo'],
    );
    
    _allPosts.add(newPost);
    updateTuttiCount();
  }

  // Simula la rimozione di un post
  void removeMockPost(String postId) {
    _allPosts.removeWhere((post) => post.id == postId);
    updateTuttiCount();
  }

  // Esporta la struttura delle cartelle (per backup futuro)
  Map<String, dynamic> exportFolderStructure() {
    Map<String, dynamic> exportFolder(MockFolder folder) {
      return {
        'name': folder.name,
        'count': folder.count,
        'level': folder.level,
        'isSpecial': folder.isSpecial,
        'children': folder.children.map((child) => exportFolder(child)).toList(),
      };
    }
    
    return {
      'version': '1.0.0',
      'exportDate': DateTime.now().toIso8601String(),
      'folders': _folders.map((folder) => exportFolder(folder)).toList(),
      'totalPosts': _allPosts.length,
    };
  }

  // Reset delle cartelle ai valori di default
  void resetToDefault() {
    _folders.clear();
    _allPosts.clear();
    initializeFolders();
  }

  // Valida il nome di una cartella
  String? validateFolderName(String name) {
    if (name.trim().isEmpty) {
      return 'Il nome non può essere vuoto';
    }
    if (name.length > 50) {
      return 'Il nome è troppo lungo (max 50 caratteri)';
    }
    if (name.contains(RegExp(r'[<>:"/\\|?*]'))) {
      return 'Il nome contiene caratteri non validi';
    }
    return null; // Nome valido
  }

  // Ottiene suggerimenti per nomi di cartelle
  List<String> getFolderNameSuggestions() {
    return [
      'Lavoro',
      'Studio', 
      'Hobby',
      'Acquisti',
      'Casa',
      'Finanze',
      'Salute',
      'Eventi',
      'Ispirazioni',
      'Tutorial',
    ];
  }
}