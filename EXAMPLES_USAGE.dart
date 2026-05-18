// ============================================================================
// ESEMPI PRATICI DI UTILIZZO DEL SISTEMA UNIFICATO
// ============================================================================
// Questo file contiene esempi concreti di come usare il nuovo sistema
// unificato per la gestione cartelle, sottocartelle e anteprime.
// ============================================================================

import 'package:flutter/material.dart';
import 'lib/services/folder_management_unified.dart';
import 'lib/models.dart';
import 'lib/models/folder.dart';
import 'lib/data_service.dart';

// ============================================================================
// ESEMPIO 1: Inizializzazione e Caricamento Dati
// ============================================================================

class Example1_LoadingData {
  Future<void> loadAllData() async {
    print('=== ESEMPIO 1: Caricamento Completo ===\n');
    
    // STEP 1: Carica cartelle dal database
    print('📚 Caricando cartelle dal database...');
    List<Folder> dbFolders = await DataService.instance.getFolders();
    print('✅ ${dbFolders.length} cartelle caricate\n');
    
    // STEP 2: Sincronizza cartelle (DB → UI)
    print('🔄 Sincronizzando cartelle...');
    List<MockFolder> uiFolders = await UnifiedFolderManager.sync
        .syncFoldersFromDatabase(dbFolders);
    print('✅ ${uiFolders.length} cartelle pronte per UI\n');
    
    // STEP 3: Carica post dal database
    print('📝 Caricando post dal database...');
    List<SavedPost> dbPosts = await DataService.instance.getPosts();
    print('✅ ${dbPosts.length} post caricati\n');
    
    // STEP 4: Sincronizza post
    print('🔄 Sincronizzando post...');
    List<MockPost> uiPosts = await UnifiedFolderManager.posts
        .syncPostsFromDatabase(dbPosts, dbFolders, uiFolders);
    print('✅ ${uiPosts.length} post pronti per UI\n');
    
    // STEP 5: Aggiorna conteggi cartelle
    print('📊 Aggiornando conteggi...');
    UnifiedFolderManager.utils.updateAllFolderCounts(uiFolders, uiPosts);
    print('✅ Conteggi aggiornati\n');
    
    // STEP 6: Stampa struttura (debug)
    print('🌳 Struttura cartelle:');
    UnifiedFolderManager.utils.printFolderStructure(uiFolders);
    
    print('\n=== Fine Esempio 1 ===\n');
  }
}

// ============================================================================
// ESEMPIO 2: Creazione Cartelle e Sottocartelle
// ============================================================================

class Example2_CreatingFolders {
  Future<void> createFolderHierarchy() async {
    print('=== ESEMPIO 2: Creazione Cartelle ===\n');
    
    // METODO 1: Crea cartella root semplice
    print('📁 Metodo 1: Creazione cartella root...');
    await UnifiedFolderManager.operations.createRootFolder("Progetti");
    print('✅ Cartella "Progetti" creata\n');
    
    // METODO 2: Crea sottocartella
    print('📂 Metodo 2: Creazione sottocartella...');
    
    // Prima trova la cartella parent nell'UI
    List<Folder> dbFolders = await DataService.instance.getFolders();
    List<MockFolder> uiFolders = await UnifiedFolderManager.sync
        .syncFoldersFromDatabase(dbFolders);
    
    MockFolder? progettiFolder = uiFolders.firstWhere(
      (f) => f.name == "Progetti" && !f.isSpecial,
      orElse: () => throw Exception('Cartella Progetti non trovata'),
    );
    
    await UnifiedFolderManager.operations.createSubfolder(
      progettiFolder, 
      "Flutter"
    );
    print('✅ Sottocartella "Flutter" creata sotto "Progetti"\n');
    
    // METODO 3: Crea gerarchia completa da path
    print('🎯 Metodo 3: Creazione gerarchia completa...');
    String finalFolderId = await UnifiedFolderManager.hierarchy
        .createHierarchyFromPath("Tech › Mobile › iOS › SwiftUI");
    
    print('✅ Gerarchia creata!');
    print('   Path: Tech › Mobile › iOS › SwiftUI');
    print('   ID finale: $finalFolderId\n');
    
    print('=== Fine Esempio 2 ===\n');
  }
}

// ============================================================================
// ESEMPIO 3: Salvataggio Post in Cartelle
// ============================================================================

class Example3_SavingPosts {
  Future<void> savePostToSpecificFolder() async {
    print('=== ESEMPIO 3: Salvataggio Post ===\n');
    
    // SCENARIO: Vogliamo salvare un post in "Tech › Flutter › Tips"
    
    // STEP 1: Assicurati che la gerarchia esista
    print('🔨 Creando gerarchia se necessario...');
    String tipsFolderId = await UnifiedFolderManager.hierarchy
        .createHierarchyFromPath("Tech › Flutter › Tips");
    print('✅ Cartella pronta (ID: $tipsFolderId)\n');
    
    // STEP 2: Salva il post
    print('💾 Salvando post...');
    SavedPost post = await UnifiedFolderManager.posts.savePostToFolder(
      url: "https://flutter.dev/docs/cookbook",
      title: "Flutter Cookbook - Ricette e Best Practices",
      description: "Una collezione di ricette per sviluppare app Flutter",
      imageUrl: "https://flutter.dev/images/cookbook.png",
      tags: ["flutter", "dart", "mobile", "tips"],
      folderId: tipsFolderId,
    );
    
    print('✅ Post salvato!');
    print('   ID: ${post.id}');
    print('   Titolo: ${post.title}');
    print('   Cartella: $tipsFolderId\n');
    
    print('=== Fine Esempio 3 ===\n');
  }
  
  Future<void> savePostFromSharing() async {
    print('=== ESEMPIO 3B: Post da Condivisione ===\n');
    
    // SCENARIO: Utente condivide link da browser
    // e seleziona cartella "Ricette › Dolci"
    
    print('🔗 Link condiviso: https://giallozafferano.it/tiramisu');
    print('📂 Cartella selezionata: Ricette › Dolci\n');
    
    // STEP 1: Crea/Trova cartella target
    String dolciFolderId = await UnifiedFolderManager.hierarchy
        .createHierarchyFromPath("Ricette › Dolci");
    
    // STEP 2: Salva post
    SavedPost post = await UnifiedFolderManager.posts.savePostToFolder(
      url: "https://giallozafferano.it/tiramisu",
      title: "Tiramisù - Ricetta Originale",
      description: "Il classico dolce italiano al caffè e mascarpone",
      imageUrl: "https://giallozafferano.it/images/tiramisu.jpg",
      tags: ["ricette", "dolci", "italiano"],
      folderId: dolciFolderId,
    );
    
    print('✅ Post salvato da condivisione!');
    print('   Ora visibile in: Ricette › Dolci\n');
    
    print('=== Fine Esempio 3B ===\n');
  }
}

// ============================================================================
// ESEMPIO 4: Generazione Anteprime Cartelle
// ============================================================================

class Example4_FolderPreviews {
  Future<void> generateFolderPreviews() async {
    print('=== ESEMPIO 4: Anteprime Cartelle ===\n');
    
    // STEP 1: Carica dati
    List<Folder> dbFolders = await DataService.instance.getFolders();
    List<MockFolder> uiFolders = await UnifiedFolderManager.sync
        .syncFoldersFromDatabase(dbFolders);
    
    List<SavedPost> dbPosts = await DataService.instance.getPosts();
    List<MockPost> uiPosts = await UnifiedFolderManager.posts
        .syncPostsFromDatabase(dbPosts, dbFolders, uiFolders);
    
    // STEP 2: Trova cartella "Tech"
    MockFolder? techFolder = uiFolders.firstWhere(
      (f) => f.name == "Tech" && !f.isSpecial,
      orElse: () => throw Exception('Cartella Tech non trovata'),
    );
    
    // STEP 3: Genera anteprima
    print('🖼️ Generando anteprima per: ${techFolder.name}');
    FolderPreviewStats stats = UnifiedFolderManager.preview
        .getFolderPreviewImages(techFolder, uiPosts, maxImages: 4);
    
    print('📊 Statistiche anteprima:');
    print('   - Immagini totali disponibili: ${stats.totalImagesAvailable}');
    print('   - Immagini recenti: ${stats.recentImagesCount}');
    print('   - Sufficiente per griglia: ${stats.hasEnoughForGrid}');
    print('   - URL immagini:');
    for (var i = 0; i < stats.imageUrls.length; i++) {
      print('     ${i + 1}. ${stats.imageUrls[i]}');
    }
    print('');
    
    // STEP 4: Verifica se può mostrare anteprima
    bool canShow = UnifiedFolderManager.preview
        .canShowImagePreview(techFolder, uiPosts);
    
    print('✅ Può mostrare anteprima: $canShow\n');
    
    // STEP 5: Statistiche complete
    Map<String, dynamic> detailedStats = UnifiedFolderManager.preview
        .getFolderImageStats(techFolder, uiPosts);
    
    print('📈 Statistiche complete:');
    detailedStats.forEach((key, value) {
      print('   - $key: $value');
    });
    
    print('\n=== Fine Esempio 4 ===\n');
  }
  
  Future<void> generatePreviewsForAllFolders() async {
    print('=== ESEMPIO 4B: Anteprime per Tutte le Cartelle ===\n');
    
    // Carica dati
    List<Folder> dbFolders = await DataService.instance.getFolders();
    List<MockFolder> uiFolders = await UnifiedFolderManager.sync
        .syncFoldersFromDatabase(dbFolders);
    
    List<SavedPost> dbPosts = await DataService.instance.getPosts();
    List<MockPost> uiPosts = await UnifiedFolderManager.posts
        .syncPostsFromDatabase(dbPosts, dbFolders, uiFolders);
    
    // Genera anteprime per tutte le cartelle
    print('📊 Generando anteprime per ${uiFolders.length} cartelle...\n');
    
    for (var folder in uiFolders) {
      if (folder.isSpecial) continue; // Salta "Tutti"
      
      final stats = UnifiedFolderManager.preview
          .getFolderPreviewImages(folder, uiPosts, maxImages: 4);
      
      String path = UnifiedFolderManager.hierarchy.buildFolderPath(folder);
      
      print('📁 $path');
      print('   Immagini: ${stats.recentImagesCount}/4');
      print('   Può mostrare griglia: ${stats.hasEnoughForGrid ? "✅" : "❌"}\n');
    }
    
    print('=== Fine Esempio 4B ===\n');
  }
}

// ============================================================================
// ESEMPIO 5: Widget per Visualizzare Anteprime
// ============================================================================

class Example5_FolderCardWidget extends StatelessWidget {
  final MockFolder folder;
  final List<MockPost> allPosts;
  
  const Example5_FolderCardWidget({
    Key? key,
    required this.folder,
    required this.allPosts,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // Genera statistiche anteprima
    final stats = UnifiedFolderManager.preview
        .getFolderPreviewImages(folder, allPosts, maxImages: 4);
    
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Stack(
        children: [
          // Anteprima immagini o fallback
          Positioned.fill(
            child: stats.imageUrls.isNotEmpty
                ? _buildImagePreview(stats.imageUrls)
                : _buildDefaultPreview(),
          ),
          
          // Overlay gradiente
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
          ),
          
          // Info cartella
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  folder.count,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildImagePreview(List<String> imageUrls) {
    // Layout dipende dal numero di immagini
    if (imageUrls.length == 1) {
      return _buildSingleImage(imageUrls[0]);
    } else if (imageUrls.length == 2) {
      return _buildTwoImages(imageUrls);
    } else if (imageUrls.length == 3) {
      return _buildThreeImages(imageUrls);
    } else {
      return _buildFourImages(imageUrls);
    }
  }
  
  Widget _buildSingleImage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
  
  Widget _buildTwoImages(List<String> urls) {
    return Column(
      children: [
        Expanded(child: Image.network(urls[0], fit: BoxFit.cover)),
        Expanded(child: Image.network(urls[1], fit: BoxFit.cover)),
      ],
    );
  }
  
  Widget _buildThreeImages(List<String> urls) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: Image.network(urls[0], fit: BoxFit.cover)),
              Expanded(child: Image.network(urls[1], fit: BoxFit.cover)),
            ],
          ),
        ),
        Expanded(child: Image.network(urls[2], fit: BoxFit.cover)),
      ],
    );
  }
  
  Widget _buildFourImages(List<String> urls) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: Image.network(urls[0], fit: BoxFit.cover)),
              Expanded(child: Image.network(urls[1], fit: BoxFit.cover)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: Image.network(urls[2], fit: BoxFit.cover)),
              Expanded(child: Image.network(urls[3], fit: BoxFit.cover)),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildDefaultPreview() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            folder.color.withOpacity(0.3),
            folder.color.withOpacity(0.1),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.folder_outlined,
          color: folder.color.withOpacity(0.5),
          size: 48,
        ),
      ),
    );
  }
}

// ============================================================================
// ESEMPIO 6: Operazioni su Cartelle (CRUD)
// ============================================================================

class Example6_FolderOperations {
  Future<void> performCRUDOperations() async {
    print('=== ESEMPIO 6: Operazioni CRUD ===\n');
    
    // Setup iniziale
    List<Folder> dbFolders = await DataService.instance.getFolders();
    List<MockFolder> uiFolders = await UnifiedFolderManager.sync
        .syncFoldersFromDatabase(dbFolders);
    
    // OPERAZIONE 1: Rinomina
    print('✏️ Operazione 1: Rinomina cartella...');
    MockFolder? techFolder = uiFolders.firstWhere(
      (f) => f.name == "Tech" && !f.isSpecial,
      orElse: () => throw Exception('Cartella Tech non trovata'),
    );
    
    await UnifiedFolderManager.operations.renameFolder(
      techFolder, 
      "Tecnologia"
    );
    print('✅ "Tech" rinominata in "Tecnologia"\n');
    
    // OPERAZIONE 2: Sposta
    print('📦 Operazione 2: Sposta cartella...');
    
    // Trova cartella da spostare e nuovo parent
    MockFolder? flutterFolder = techFolder.children.firstWhere(
      (f) => f.name == "Flutter",
      orElse: () => throw Exception('Cartella Flutter non trovata'),
    );
    
    MockFolder? progettiFolder = uiFolders.firstWhere(
      (f) => f.name == "Progetti" && !f.isSpecial,
      orElse: () => throw Exception('Cartella Progetti non trovata'),
    );
    
    await UnifiedFolderManager.operations.moveFolder(
      flutterFolder,
      progettiFolder,
    );
    print('✅ "Flutter" spostata sotto "Progetti"\n');
    
    // OPERAZIONE 3: Elimina
    print('🗑️ Operazione 3: Elimina cartella...');
    
    // Crea cartella temporanea per test
    await UnifiedFolderManager.operations.createRootFolder("TempTest");
    
    // Ricarica folders
    dbFolders = await DataService.instance.getFolders();
    uiFolders = await UnifiedFolderManager.sync
        .syncFoldersFromDatabase(dbFolders);
    
    MockFolder? tempFolder = uiFolders.firstWhere(
      (f) => f.name == "TempTest" && !f.isSpecial,
      orElse: () => throw Exception('Cartella TempTest non trovata'),
    );
    
    await UnifiedFolderManager.operations.deleteFolder(tempFolder);
    print('✅ "TempTest" eliminata (post spostati in "Tutti")\n');
    
    print('=== Fine Esempio 6 ===\n');
  }
}

// ============================================================================
// ESEMPIO 7: Utility e Debug
// ============================================================================

class Example7_UtilityFunctions {
  Future<void> useUtilityFunctions() async {
    print('=== ESEMPIO 7: Funzioni Utility ===\n');
    
    // Setup
    List<Folder> dbFolders = await DataService.instance.getFolders();
    List<MockFolder> uiFolders = await UnifiedFolderManager.sync
        .syncFoldersFromDatabase(dbFolders);
    
    List<SavedPost> dbPosts = await DataService.instance.getPosts();
    List<MockPost> uiPosts = await UnifiedFolderManager.posts
        .syncPostsFromDatabase(dbPosts, dbFolders, uiFolders);
    
    // UTILITY 1: Conta post ricorsivamente
    print('📊 Utility 1: Conteggio post ricorsivo\n');
    for (var folder in uiFolders) {
      if (folder.isSpecial) continue;
      
      int count = UnifiedFolderManager.utils
          .countPostsInFolder(folder, uiPosts);
      
      String path = UnifiedFolderManager.hierarchy.buildFolderPath(folder);
      print('   $path: $count post');
    }
    print('');
    
    // UTILITY 2: Aggiorna tutti i conteggi
    print('🔄 Utility 2: Aggiornamento conteggi\n');
    UnifiedFolderManager.utils.updateAllFolderCounts(uiFolders, uiPosts);
    print('   ✅ Conteggi aggiornati per ${uiFolders.length} cartelle\n');
    
    // UTILITY 3: Ottieni tutti i post ricorsivi
    print('📝 Utility 3: Post ricorsivi da cartella\n');
    MockFolder? techFolder = uiFolders.firstWhere(
      (f) => f.name == "Tech" && !f.isSpecial,
      orElse: () => throw Exception('Cartella Tech non trovata'),
    );
    
    List<MockPost> techPosts = UnifiedFolderManager.utils
        .getAllPostsRecursive(techFolder, uiPosts);
    
    print('   Cartella "Tech" contiene ${techPosts.length} post (incluse sottocartelle)\n');
    
    // UTILITY 4: Stampa struttura
    print('🌳 Utility 4: Stampa struttura\n');
    UnifiedFolderManager.utils.printFolderStructure(uiFolders);
    
    print('\n=== Fine Esempio 7 ===\n');
  }
}

// ============================================================================
// ESEMPIO 8: Scenario Completo End-to-End
// ============================================================================

class Example8_CompleteScenario {
  Future<void> completeUserJourney() async {
    print('=== ESEMPIO 8: Scenario Completo ===\n');
    print('📖 Storia: Utente salva ricette in cartelle organizzate\n');
    
    // ========== FASE 1: Setup Iniziale ==========
    print('🔧 FASE 1: Setup Iniziale\n');
    
    List<Folder> dbFolders = await DataService.instance.getFolders();
    List<MockFolder> uiFolders = await UnifiedFolderManager.sync
        .syncFoldersFromDatabase(dbFolders);
    
    List<SavedPost> dbPosts = await DataService.instance.getPosts();
    List<MockPost> uiPosts = await UnifiedFolderManager.posts
        .syncPostsFromDatabase(dbPosts, dbFolders, uiFolders);
    
    print('   ✅ Caricati: ${uiFolders.length} cartelle, ${uiPosts.length} post\n');
    
    // ========== FASE 2: Creazione Struttura ==========
    print('📁 FASE 2: Creazione Struttura Cartelle\n');
    
    await UnifiedFolderManager.hierarchy
        .createHierarchyFromPath("Ricette › Primi › Pasta");
    print('   ✅ Creata: Ricette › Primi › Pasta\n');
    
    await UnifiedFolderManager.hierarchy
        .createHierarchyFromPath("Ricette › Secondi › Carne");
    print('   ✅ Creata: Ricette › Secondi › Carne\n');
    
    await UnifiedFolderManager.hierarchy
        .createHierarchyFromPath("Ricette › Dolci");
    print('   ✅ Creata: Ricette › Dolci\n');
    
    // ========== FASE 3: Salvataggio Ricette ==========
    print('💾 FASE 3: Salvataggio Ricette\n');
    
    // Ricetta 1: Carbonara
    String pastaFolderId = await UnifiedFolderManager.hierarchy
        .createHierarchyFromPath("Ricette › Primi › Pasta");
    
    await UnifiedFolderManager.posts.savePostToFolder(
      url: "https://giallozafferano.it/carbonara",
      title: "Carbonara - Ricetta Originale Romana",
      imageUrl: "https://giallozafferano.it/images/carbonara.jpg",
      tags: ["ricette", "pasta", "primi"],
      folderId: pastaFolderId,
    );
    print('   ✅ Salvata: Carbonara\n');
    
    // Ricetta 2: Amatriciana
    await UnifiedFolderManager.posts.savePostToFolder(
      url: "https://giallozafferano.it/amatriciana",
      title: "Amatriciana - Ricetta Tradizionale",
      imageUrl: "https://giallozafferano.it/images/amatriciana.jpg",
      tags: ["ricette", "pasta", "primi"],
      folderId: pastaFolderId,
    );
    print('   ✅ Salvata: Amatriciana\n');
    
    // Ricetta 3: Tiramisù
    String dolciFolderId = await UnifiedFolderManager.hierarchy
        .createHierarchyFromPath("Ricette › Dolci");
    
    await UnifiedFolderManager.posts.savePostToFolder(
      url: "https://giallozafferano.it/tiramisu",
      title: "Tiramisù - Il Dolce Italiano più Amato",
      imageUrl: "https://giallozafferano.it/images/tiramisu.jpg",
      tags: ["ricette", "dolci"],
      folderId: dolciFolderId,
    );
    print('   ✅ Salvata: Tiramisù\n');
    
    // ========== FASE 4: Ricarica e Sincronizzazione ==========
    print('🔄 FASE 4: Sincronizzazione\n');
    
    dbFolders = await DataService.instance.getFolders();
    uiFolders = await UnifiedFolderManager.sync
        .syncFoldersFromDatabase(dbFolders);
    
    dbPosts = await DataService.instance.getPosts();
    uiPosts = await UnifiedFolderManager.posts
        .syncPostsFromDatabase(dbPosts, dbFolders, uiFolders);
    
    UnifiedFolderManager.utils.updateAllFolderCounts(uiFolders, uiPosts);
    
    print('   ✅ Sincronizzazione completata\n');
    
    // ========== FASE 5: Visualizzazione Struttura ==========
    print('🌳 FASE 5: Struttura Finale\n');
    UnifiedFolderManager.utils.printFolderStructure(uiFolders);
    print('');
    
    // ========== FASE 6: Anteprime ==========
    print('🖼️ FASE 6: Generazione Anteprime\n');
    
    MockFolder? ricetteFolder = uiFolders.firstWhere(
      (f) => f.name == "Ricette" && !f.isSpecial,
      orElse: () => throw Exception('Cartella Ricette non trovata'),
    );
    
    final stats = UnifiedFolderManager.preview
        .getFolderPreviewImages(ricetteFolder, uiPosts, maxImages: 4);
    
    print('   📊 Anteprima cartella "Ricette":');
    print('      - Immagini disponibili: ${stats.totalImagesAvailable}');
    print('      - Per anteprima: ${stats.recentImagesCount}');
    print('      - Può mostrare griglia: ${stats.hasEnoughForGrid ? "✅" : "❌"}\n');
    
    // ========== FASE 7: Statistiche Finali ==========
    print('📈 FASE 7: Statistiche Finali\n');
    
    int totalFolders = uiFolders.where((f) => !f.isSpecial).length;
    int totalPosts = uiPosts.length;
    int ricettePosts = UnifiedFolderManager.utils
        .countPostsInFolder(ricetteFolder, uiPosts);
    
    print('   📚 Cartelle totali: $totalFolders');
    print('   📝 Post totali: $totalPosts');
    print('   🍝 Ricette salvate: $ricettePosts\n');
    
    print('✅ SCENARIO COMPLETATO CON SUCCESSO!\n');
    print('=== Fine Esempio 8 ===\n');
  }
}

// ============================================================================
// FUNZIONE MAIN PER ESEGUIRE TUTTI GLI ESEMPI
// ============================================================================

void main() async {
  print('\n');
  print('╔═══════════════════════════════════════════════════════════╗');
  print('║   ESEMPI DI UTILIZZO - SISTEMA GESTIONE CARTELLE         ║');
  print('╚═══════════════════════════════════════════════════════════╝');
  print('\n');
  
  // Decommentare l'esempio che vuoi eseguire:
  
  // await Example1_LoadingData().loadAllData();
  // await Example2_CreatingFolders().createFolderHierarchy();
  // await Example3_SavingPosts().savePostToSpecificFolder();
  // await Example3_SavingPosts().savePostFromSharing();
  // await Example4_FolderPreviews().generateFolderPreviews();
  // await Example4_FolderPreviews().generatePreviewsForAllFolders();
  // await Example6_FolderOperations().performCRUDOperations();
  // await Example7_UtilityFunctions().useUtilityFunctions();
  
  // SCENARIO COMPLETO (raccomandato per iniziare):
  await Example8_CompleteScenario().completeUserJourney();
  
  print('\n');
  print('╔═══════════════════════════════════════════════════════════╗');
  print('║                    FINE ESEMPI                            ║');
  print('╚═══════════════════════════════════════════════════════════╝');
  print('\n');
}



