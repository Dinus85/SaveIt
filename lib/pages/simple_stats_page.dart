// simple_stats_page.dart
// Pagina statistiche AVANZATA con analytics comportamentali e micro-timing

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/theme_helpers.dart';
import '../services/simple_analytics_service.dart';
import '../services/folder_service.dart';   // NUOVO: Service cartelle
import '../advanced_analytics_service.dart';          // NUOVO: Service avanzato
import '../advanced_analytics_models.dart';           // NUOVO: Modelli avanzati
import 'dart:math' as math;

class SimpleStatsPage extends StatefulWidget {
  final bool isDarkTheme;

  const SimpleStatsPage({Key? key, required this.isDarkTheme}) : super(key: key);

  @override
  _SimpleStatsPageState createState() => _SimpleStatsPageState();
}

class _SimpleStatsPageState extends State<SimpleStatsPage> with TickerProviderStateMixin {
  final SimpleAnalyticsService _analytics = SimpleAnalyticsService();
  final AdvancedAnalyticsService _advancedAnalytics = AdvancedAnalyticsService(); // NUOVO
  final FolderService _folderService = FolderService(); // NUOVO: Service cartelle
  
  SimpleStats? _stats;
  AdvancedAnalyticsData? _advancedStats; // NUOVO: Statistiche avanzate
  bool _isLoading = true;
  
  // Controllers per animazioni
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadStats();
  }

  @override
  void dispose() {
    // ✅ CRITICO: Salva sessione avanzata prima di chiudere pagina
    _advancedAnalytics.endSmartSession();
    
    _fadeController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    
    try {
      // Carica statistiche base
      await _analytics.initialize();
      final stats = _analytics.calculateStats();
      print('DEBUG: Stats base caricate');
      
      // NUOVO: Carica statistiche avanzate
      await _advancedAnalytics.initialize();
      print('DEBUG: AdvancedAnalytics inizializzato');
      
      print('DEBUG: Advanced analytics - ${_advancedAnalytics.totalAdvancedEvents} eventi, ${_advancedAnalytics.totalSessions} sessioni');

      // NUOVO: Calcola metriche organizzative reali
      await _folderService.initializeFolders();
      final orgMetrics = await _folderService.calculateOrganizationalMetrics();
      print('DEBUG: Metriche organizzative calcolate - Cartelle: ${orgMetrics.totalFolders}, Profondità: ${orgMetrics.avgFolderDepth}');
      
      final advancedStats = await _advancedAnalytics.calculateFullAdvancedStats();
      print('DEBUG: AdvancedStats calcolate: ${advancedStats.sessions.length} sessioni');
      
      // NUOVO: Crea una nuova istanza con le metriche organizzative reali
      final advancedStatsWithRealMetrics = AdvancedAnalyticsData(
        sessions: advancedStats.sessions,
        contentInteractions: advancedStats.contentInteractions,
        organizationalMetrics: orgMetrics, // Metriche reali
        behavioralStats: advancedStats.behavioralStats,
        microTimingStats: advancedStats.microTimingStats,
        contentQualityMetrics: advancedStats.contentQualityMetrics,
        insights: advancedStats.insights,
        lastCalculated: advancedStats.lastCalculated,
      );
      
      setState(() {
        _stats = stats;
        _advancedStats = advancedStatsWithRealMetrics; // Usa le metriche reali
        _isLoading = false;
      });
      
      _fadeController.forward();
    } catch (e) {
      print('DEBUG ERRORE: Caricamento statistiche fallito: $e');
      setState(() => _isLoading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(widget.isDarkTheme);
    
    return Scaffold(
      backgroundColor: themeColors.mainBackgroundColor,
      appBar: _buildAppBar(themeColors),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Colors.blue))
          : _stats == null
              ? _buildErrorState(themeColors)
              : _buildStatsContent(themeColors),
      bottomNavigationBar: _buildBottomNav(themeColors),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeColors themeColors) {
    return AppBar(
      backgroundColor: themeColors.mainBackgroundColor,
      elevation: 0,
      titleSpacing: 16,
      title: Text(
        'Statistiche',
        style: TextStyle(
          color: themeColors.titleColor,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: themeColors.iconColor, size: 28),
        onPressed: () => Navigator.pop(context),
      ),
      toolbarHeight: 80,
      actions: [
        IconButton(
          icon: Icon(Icons.refresh, color: themeColors.iconColor),
          onPressed: _loadStats,
        ),
        _buildMoreMenu(themeColors),
      ],
    );
  }

  Widget _buildMoreMenu(ThemeColors themeColors) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: themeColors.iconColor),
      onSelected: (value) async {
        switch (value) {
          case 'export':
            _exportData();
            break;
          case 'export_advanced': // NUOVO
            _exportAdvancedData();
            break;
          case 'clear':
            _showClearDataDialog();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(Icons.download, color: themeColors.textColor),
              SizedBox(width: 8),
              Text('Esporta Base', style: TextStyle(color: themeColors.textColor)),
            ],
          ),
        ),
        if (_advancedStats != null) // NUOVO
          PopupMenuItem(
            value: 'export_advanced',
            child: Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue),
                SizedBox(width: 8),
                Text('Esporta Avanzate', style: TextStyle(color: Colors.blue)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text('Cancella Dati', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav(ThemeColors themeColors) {
    return SafeArea(  // <-- AGGIUNTO QUESTO
      child: Container(
        color: themeColors.bottomBarColor,
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              icon: Icon(Icons.home, color: themeColors.iconColor, size: 28),
            ),
            FloatingActionButton(
              onPressed: () => _showCreateFolderDialog(),
              backgroundColor: Colors.white,
              child: Icon(Icons.add, color: Colors.black, size: 28),
              mini: false,
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.person, color: themeColors.iconColor, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeColors themeColors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, color: themeColors.hintColor, size: 64),
          SizedBox(height: 16),
          Text(
            'Nessun dato disponibile',
            style: TextStyle(color: themeColors.textColor, fontSize: 18),
          ),
          SizedBox(height: 8),
          Text(
            'Usa l\'app per vedere le statistiche',
            style: TextStyle(color: themeColors.hintColor, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsContent(ThemeColors themeColors) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sezioni base
            _buildSummarySection(themeColors),
            SizedBox(height: 24),
            _buildActivitySection(themeColors),
            SizedBox(height: 24),
            _buildContentSection(themeColors),
            SizedBox(height: 24),
            
            // Informazioni App alla fine
            _buildAppInfoSection(themeColors),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // SEZIONI BASE ESISTENTI (MODIFICATE)
  // ============================================================================

  Widget _buildSummarySection(ThemeColors themeColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // MODIFICATO: Solo il titolo, senza pulsante Vista Avanzata
        Text(
          'Panoramica',
          style: TextStyle(
            color: themeColors.titleColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        
        GridView.count(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _buildStatCard(
              'Aperture Medie', 
              _calculateWeeklyAverageOpens(),
              Icons.trending_up,
              Colors.blue,
              themeColors,
              subtitle: 'settimanali',
              statKey: 'weekly_opens', // MODIFICATO
            ),
            _buildStatCard(
              'Post Salvati', 
              (_folderService.getAccountStats()['totalPosts'] ?? 0).toString(),
              Icons.bookmark,
              Colors.green,
              themeColors,
              statKey: 'total_posts', // MODIFICATO
            ),
            _buildStatCard(
              'Totale Cartelle', 
              (_folderService.getAccountStats()['totalFolders'] ?? 0).toString(),
              Icons.folder,
              Colors.orange,
              themeColors,
              statKey: 'total_folders', // MODIFICATO
            ),
            _buildStatCard(
              'Ricerche Medie', 
              _calculateWeeklyAverageSearches(),
              Icons.search,
              Colors.purple,
              themeColors,
              subtitle: 'settimanali',
              statKey: 'weekly_searches', // MODIFICATO
            ),
          ],
        ),
        
        SizedBox(height: 16),
        
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Giorni Consecutivi', 
                _stats!.streakDays.toString(),
                Icons.local_fire_department,
                Colors.red,
                themeColors,
                subtitle: 'streak',
                statKey: 'streak_days', // AGGIUNTO
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Tempo Medio', 
                _calculateAverageTime(),
                Icons.timer,
                Colors.teal,
                themeColors,
                subtitle: 'per sessione',
                statKey: 'average_time', // MODIFICATO
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActivitySection(ThemeColors themeColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modelli di Utilizzo',
          style: TextStyle(
            color: themeColors.titleColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        
        _buildWeeklyUsageCard(themeColors),
        SizedBox(height: 16),
        _buildHourlyUsageCard(themeColors),
      ],
    );
  }

  Widget _buildContentSection(ThemeColors themeColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contenuti',
          style: TextStyle(
            color: themeColors.titleColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        
        if (_stats!.topFolders.isNotEmpty) ...[
          _buildTopItemsCard(
            'Cartelle Più Utilizzate',
            _stats!.topFolders,
            Icons.folder,
            Colors.orange,
            themeColors,
          ),
          SizedBox(height: 16),
        ],
        
        // MODIFICATO: Usa post reali invece di eventi storici
        FutureBuilder<Map<String, int>>(
          future: _getTopSocialNetworks(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return Column(
                children: [
                  _buildTopItemsCard(
                    'Social Network',
                    snapshot.data!,
                    Icons.public,
                    Colors.blue,
                    themeColors,
                  ),
                  SizedBox(height: 12),
                ],
              );
            }
            return SizedBox.shrink();
          },
        ),
        
        // NUOVO: Sezione Siti Web
        FutureBuilder<Map<String, int>>(
          future: _getTopWebsites(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return Column(
                children: [
                  _buildTopItemsCard(
                    'Siti Web',
                    snapshot.data!,
                    Icons.language,
                    Colors.green,
                    themeColors,
                  ),
                  SizedBox(height: 12),
                ],
              );
            }
            return SizedBox.shrink();
          },
        ),
        
        // NUOVO: Sezione Hashtag più utilizzati
        FutureBuilder<Map<String, int>>(
          future: _getTopHashtags(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return Column(
                children: [
                  _buildTopItemsCard(
                    'Hashtag Più Utilizzati',
                    snapshot.data!,
                    Icons.tag,
                    Colors.purple,
                    themeColors,
                    isHashtag: true,
                  ),
                  SizedBox(height: 12),
                ],
              );
            }
            return SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _buildAppInfoSection(ThemeColors themeColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Informazioni App',
          style: TextStyle(
            color: themeColors.titleColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildInfoRow('Primo Utilizzo', _formatDate(_stats!.firstUse), themeColors),
              _buildInfoRow('Ultimo Utilizzo', _formatDate(_stats!.lastUse), themeColors),
              _buildInfoRow('Versione App', '1.0.0', themeColors),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // NUOVE SEZIONI AVANZATE
  // ============================================================================


  Widget _buildAdvancedSummarySection(ThemeColors themeColors) {
    // ✅ NUOVO: Gestisci caso senza dati (utente nuovo)
    if (_advancedStats!.sessions.isEmpty && 
        _advancedStats!.contentInteractions.isEmpty) {
      return Container(
        padding: EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.analytics_outlined, 
                size: 80, 
                color: themeColors.hintColor.withOpacity(0.5)
              ),
              SizedBox(height: 24),
              Text(
                'Statistiche Avanzate',
                style: TextStyle(
                  color: themeColors.textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Nessun dato disponibile',
                style: TextStyle(
                  color: themeColors.hintColor,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Usa SaveIn! per generare statistiche comportamentali dettagliate',
                style: TextStyle(
                  color: themeColors.hintColor,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    // ↓ CODICE ORIGINALE INIZIA QUI
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.analytics, color: Colors.blue, size: 24),
            SizedBox(width: 8),
            Text(
              'Analytics Avanzate',
              style: TextStyle(
                color: themeColors.titleColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        
        GridView.count(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _buildStatCard(
              'Sessione Media', 
              '${_advancedStats!.behavioralStats.avgSessionTime.inMinutes}m ${_advancedStats!.behavioralStats.avgSessionTime.inSeconds % 60}s',
              Icons.timer,
              Colors.blue,
              themeColors,
              statKey: 'avg_session_time',
            ),
            _buildStatCard(
              'Cartelle Totali', 
              _advancedStats!.organizationalMetrics.totalFolders.toString(),
              Icons.folder,
              Colors.blue,
              themeColors,
              statKey: 'total_folders',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMicroTimingSection(ThemeColors themeColors) {
    final microTiming = _advancedStats!.microTimingStats;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, color: Colors.blue, size: 24),
            SizedBox(width: 8),
            Text(
              'Analisi Temporale Precisa',
              style: TextStyle(
                color: themeColors.titleColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        
        // Finestre di picco
        if (microTiming.peakUsageWindows.isNotEmpty)
          _buildPeakUsageCard(microTiming, themeColors),
        
        SizedBox(height: 16),
        
        // Pattern stagionali
        if (microTiming.seasonalTrends.isNotEmpty)
          _buildSeasonalTrendsCard(microTiming, themeColors),
      ],
    );
  }

  Widget _buildPeakUsageCard(MicroTimingStats microTiming, ThemeColors themeColors) {
    final peakWindows = microTiming.peakUsageWindows.entries
        .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    final topFive = peakWindows.take(5).toList();
    final sumTop = topFive.fold<double>(0.0, (sum, e) => sum + (e.value));
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Text(
                'Finestre di Picco Utilizzo',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          ...topFive.map((entry) {
            final hour = entry.key.split(':')[0];
            final window = entry.key.split(':')[1];
            final normalized = sumTop > 0 ? (entry.value / sumTop) : 0.0;
            
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$hour:$window',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: normalized,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      minHeight: 8,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    '${(normalized * 100).toInt()}%',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSeasonalTrendsCard(MicroTimingStats microTiming, ThemeColors themeColors) {
    final seasonalTrends = microTiming.seasonalTrends;
    final seasons = ['spring', 'summer', 'autumn', 'winter'];
    final seasonNames = {'spring': 'Primavera', 'summer': 'Estate', 'autumn': 'Autunno', 'winter': 'Inverno'};
    final seasonColors = {'spring': Colors.green, 'summer': Colors.orange, 'autumn': Colors.brown, 'winter': Colors.blue};
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wb_sunny, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text(
                'Trend Stagionali',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: seasons.map((season) {
              final usage = seasonalTrends[season] ?? 0;
              final maxUsage = seasonalTrends.values.isNotEmpty 
                  ? seasonalTrends.values.reduce(math.max) 
                  : 1;
              final height = maxUsage > 0 ? (usage / maxUsage * 40).clamp(4.0, 40.0) : 4.0;
              
              return Column(
                children: [
                  Container(
                    width: 30,
                    height: height,
                    decoration: BoxDecoration(
                      color: seasonColors[season],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    seasonNames[season]!,
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    usage.toString(),
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }




  Widget _buildInsightsSection(ThemeColors themeColors) {
    final insights = _advancedStats!.insights;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb, color: Colors.amber, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Insight Automatici',
                    style: TextStyle(
                      color: themeColors.titleColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Suggerimenti personalizzati basati sui tuoi pattern di utilizzo per migliorare produttività e organizzazione',
                    style: TextStyle(
                      color: themeColors.hintColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${insights.length}',
                style: TextStyle(
                  color: Colors.amber.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        
        ...insights.map((insight) => _buildInsightCard(insight, themeColors)).toList(),
      ],
    );
  }

  Widget _buildInsightCard(AnalyticsInsight insight, ThemeColors themeColors) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getInsightTypeColor(insight.type), width: 2),
        boxShadow: [
          BoxShadow(
            color: _getInsightTypeColor(insight.type).withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getInsightTypeIcon(insight.type),
                color: _getInsightTypeColor(insight.type),
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  insight.title,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getConfidenceColor(insight.confidence).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(insight.confidence * 100).toInt()}%',
                  style: TextStyle(
                    color: _getConfidenceColor(insight.confidence),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          
          Text(
            insight.description,
            style: TextStyle(
              color: Colors.black54,
              fontSize: 14,
            ),
          ),
          
          if (insight.isActionable) ...[
            SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getInsightTypeColor(insight.type).withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getInsightTypeColor(insight.type).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: _getInsightTypeColor(insight.type),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      insight.recommendation,
                      style: TextStyle(
                        color: _getInsightTypeColor(insight.type).withOpacity(0.8),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          SizedBox(height: 8),
          Text(
            'Generato ${_formatRelativeTime(insight.generatedAt)}',
            style: TextStyle(
              color: Colors.black38,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // METODI UTILITY E HELPER ESISTENTI (MANTENUTI)
  // ============================================================================

  Widget _buildStatCard(
    String title, 
    String value, 
    IconData icon, 
    Color color, 
    ThemeColors themeColors,
    {String? subtitle, String? statKey}
  ) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              // MODIFICATO: Rimossa icona info, mantenuto solo subtitle
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyUsageCard(ThemeColors themeColors) {
    final weekdays = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
    final maxUsage = _stats!.weeklyUsage.values.isEmpty 
        ? 1 
        : _stats!.weeklyUsage.values.reduce((a, b) => a > b ? a : b);
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Utilizzo Settimanale',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (index) {
              final weekday = index + 1;
              final usage = _stats!.weeklyUsage[weekday] ?? 0;
              final height = maxUsage > 0 ? (usage / maxUsage * 60).clamp(4.0, 60.0) : 4.0;
              
              return Column(
                children: [
                  Container(
                    width: 24,
                    height: height,
                    decoration: BoxDecoration(
                      color: usage > 0 ? Colors.blue : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    weekdays[index],
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    usage.toString(),
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyUsageCard(ThemeColors themeColors) {
    final timeSlots = {
      'Mattina (6-12)': _getHourRangeUsage(6, 12),
      'Pomeriggio (12-18)': _getHourRangeUsage(12, 18),
      'Sera (18-24)': _getHourRangeUsage(18, 24),
      'Notte (0-6)': _getHourRangeUsage(0, 6),
    };
    
    final totalUsage = timeSlots.values.isEmpty 
        ? 1 
        : timeSlots.values.reduce((a, b) => a + b);
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fasce Orarie Preferite',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          
          ...timeSlots.entries.map((entry) {
            final percentage = totalUsage > 0 ? (entry.value / totalUsage) : 0.0;
            final percentageText = '${(percentage * 100).toStringAsFixed(1)}%';
            
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(color: Colors.black87, fontSize: 14),
                      ),
                      Text(
                        percentageText,
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: percentage,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    minHeight: 6,
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTopItemsCard(
    String title,
    Map<String, int> items,
    IconData icon,
    Color color,
    ThemeColors themeColors,
    {bool isHashtag = false}
  ) {
    final topItems = items.entries.take(isHashtag ? 10 : 5).toList();
    
    // NUOVO: Calcola il totale per le percentuali
    final totalCount = items.values.fold<int>(0, (sum, value) => sum + value);
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          if (topItems.isEmpty)
            Text(
              'Nessun dato disponibile',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            )
          else
            ...topItems.map((entry) {
              // NUOVO: Calcola la percentuale
              final percentage = totalCount > 0 ? (entry.value / totalCount * 100) : 0.0;
              final percentageText = '${percentage.toStringAsFixed(1)}%';
              
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        isHashtag ? '#${entry.key}' : entry.key,
                        style: TextStyle(
                          color: Colors.black87, 
                          fontSize: 14,
                          fontWeight: isHashtag ? FontWeight.w600 : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // MODIFICATO: Mostra SOLO la percentuale
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        percentageText,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeColors themeColors) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // METODI UTILITY NUOVI PER STATISTICHE AVANZATE
  // ============================================================================

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.red;
  }

  Color _getEngagementColor(double engagement) {
    if (engagement >= 0.7) return Colors.green;
    if (engagement >= 0.4) return Colors.orange;
    return Colors.red;
  }

  Color _getInsightTypeColor(String type) {
    switch (type) {
      case 'productivity': return Colors.blue;
      case 'organization': return Colors.purple;
      case 'behavior': return Colors.green;
      case 'content': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _getInsightTypeIcon(String type) {
    switch (type) {
      case 'productivity': return Icons.speed;
      case 'organization': return Icons.architecture;
      case 'behavior': return Icons.psychology;
      case 'content': return Icons.high_quality;
      default: return Icons.info;
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} giorni fa';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ore fa';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minuti fa';
    } else {
      return 'Ora';
    }
  }

  int _getHourRangeUsage(int startHour, int endHour) {
    int total = 0;
    for (int hour = startHour; hour < endHour; hour++) {
      total += _stats!.hourlyUsage[hour.toString()] ?? 0;
    }
    return total;
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // ============================================================================
  // POPUP INFORMATIVI PER STATISTICHE
  // ============================================================================

  void _showStatInfoDialog(String statKey, String title, String value) {
    final statInfo = _getStatisticInfo(statKey);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statInfo['color'].withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                statInfo['icon'],
                color: statInfo['color'],
                size: 24,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Valore attuale: $value',
                    style: TextStyle(
                      color: statInfo['color'],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Descrizione principale
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.description, color: Colors.grey.shade600, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Cosa significa',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        statInfo['description'],
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Come interpretare
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: statInfo['color'].withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statInfo['color'].withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.psychology, color: statInfo['color'], size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Come interpretarlo',
                            style: TextStyle(
                              color: statInfo['color'],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        statInfo['interpretation'],
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Esempi pratici
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: Colors.amber.shade700, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Esempi pratici',
                            style: TextStyle(
                              color: Colors.amber.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      ...statInfo['examples'].map<Widget>((example) => Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: TextStyle(color: Colors.amber.shade700, fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(
                                example,
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ],
                  ),
                ),
                
                if (statInfo['tips'] != null) ...[
                  SizedBox(height: 16),
                  
                  // Consigli per migliorare
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tips_and_updates, color: Colors.green.shade700, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Consigli per migliorare',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          statInfo['tips'],
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Chiudi',
              style: TextStyle(
                color: statInfo['color'],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getStatisticInfo(String statKey) {
    switch (statKey) {
      case 'app_opens':
        return {
          'icon': Icons.launch,
          'color': Colors.blue,
          'description': 'Rappresenta il numero totale di volte che hai aperto SaveIn dall\'installazione. Questa metrica indica la frequenza con cui utilizzi l\'app e può rivelare pattern di utilizzo.',
          'interpretation': 'Un numero alto indica un utilizzo regolare e costante dell\'app. Se hai molte aperture in pochi giorni, potresti utilizzare SaveIn per brevi sessioni frequenti. Se hai poche aperture distribuite nel tempo, probabilmente fai sessioni più lunghe.',
          'examples': [
            '50 aperture in 10 giorni = ~5 aperture al giorno (utilizzo molto frequente)',
            '20 aperture in 30 giorni = utilizzo più sporadico ma regolare',
            '100 aperture in 7 giorni = potrebbero indicare sessioni molto brevi e frequenti'
          ],
          'tips': 'Un utilizzo regolare (1-3 aperture al giorno) è generalmente ottimale. Troppe aperture potrebbero indicare difficoltà nel completare le attività, mentre troppo poche potrebbero suggerire sottoutilizzo dell\'app.'
        };
        
      case 'posts_viewed':
        return {
          'icon': Icons.visibility,
          'color': Colors.green,
          'description': 'Conta tutti i post e contenuti che hai effettivamente aperto e visualizzato dopo averli salvati. Questa è una metrica chiave per misurare l\'engagement con i contenuti.',
          'interpretation': 'Un alto rapporto tra post visti e post salvati indica che salvi contenuti di qualità che ti interessano davvero. Un rapporto basso può suggerire che salvi troppo o non riesci a trovare facilmente i contenuti.',
          'examples': [
            'Se hai 100 post salvati e 80 visti = 80% di engagement (ottimo)',
            'Se hai 200 post salvati e 50 visti = 25% di engagement (da migliorare)',
            'Molte visualizzazioni ripetute = contenuti di alta qualità e riferimento'
          ],
          'tips': 'Cerca di mantenere un rapporto almeno del 50% tra contenuti visti e salvati. Se è più basso, potresti essere più selettivo nel salvare o migliorare l\'organizzazione per trovare più facilmente i contenuti.'
        };
        
      case 'folders_opened':
        return {
          'icon': Icons.folder_open,
          'color': Colors.orange,
          'description': 'Numero di volte che hai navigato ed esplorato le tue cartelle per cercare contenuti. Riflette quanto utilizzi il sistema di organizzazione che hai creato.',
          'interpretation': 'Molte aperture di cartelle indicano che navighi attivamente nella tua organizzazione. Poche aperture potrebbero significare che usi principalmente la ricerca o che la tua organizzazione non è ottimale.',
          'examples': [
            'Molte aperture + poche ricerche = buona organizzazione, navigazione intuitiva',
            'Poche aperture + molte ricerche = potresti migliorare l\'organizzazione',
            'Aperture distribuite su molte cartelle = utilizzi bene la categorizzazione'
          ],
          'tips': 'Un buon equilibrio tra navigazione per cartelle e ricerca indica un sistema organizzativo efficace. Se apri troppe cartelle per trovare qualcosa, considera di riorganizzare o usare tag più descrittivi.'
        };
        
      case 'searches':
        return {
          'icon': Icons.search,
          'color': Colors.purple,
          'description': 'Numero di volte che hai utilizzato la funzione di ricerca per trovare contenuti specifici. Un indicatore di quanto facile o difficile è trovare ciò che cerchi.',
          'interpretation': 'Molte ricerche possono indicare sia un uso attivo dell\'app che difficoltà nel trovare contenuti attraverso la navigazione. Il rapporto ricerche/successi è importante da considerare.',
          'examples': [
            'Poche ricerche + molte aperture cartelle = organizzazione chiara',
            'Molte ricerche + risultati trovati = utilizzo attivo della ricerca',
            'Molte ricerche ripetute simili = potresti migliorare l\'organizzazione'
          ],
          'tips': 'Un numero moderato di ricerche è normale. Se fai molte ricerche senza trovare quello che cerchi, considera di migliorare i tag o la struttura delle cartelle. Se trovi sempre quello che cerchi, stai usando bene la ricerca!'
        };
        
      case 'streak_days':
        return {
          'icon': Icons.local_fire_department,
          'color': Colors.red,
          'description': 'Il numero massimo di giorni consecutivi in cui hai utilizzato SaveIn. Misura la costanza e l\'abitudine nell\'uso dell\'app per la gestione dei contenuti.',
          'interpretation': 'Uno streak lungo indica che SaveIn è diventato parte della tua routine quotidiana. Streak corti ma frequenti possono essere altrettanto validi se corrispondono al tuo stile di vita.',
          'examples': [
            'Streak di 30 giorni = SaveIn è parte della routine quotidiana',
            'Streak di 7 giorni ripetuti = utilizzo settimanale regolare',
            'Streak di 3-5 giorni = utilizzo intensivo per progetti specifici'
          ],
          'tips': 'Non forzare l\'utilizzo quotidiano se non è naturale. È meglio avere un utilizzo coerente con i tuoi bisogni reali che uno streak artificiale. L\'importante è che SaveIn ti aiuti quando ne hai bisogno.'
        };
        
      case 'total_time':
        return {
          'icon': Icons.timer,
          'color': Colors.teal,
          'description': 'Una stima del tempo totale trascorso nell\'app calcolata in base alle sessioni e alle attività. Aiuta a capire quanto SaveIn è integrato nella tua routine.',
          'interpretation': 'Il tempo totale va valutato in relazione al numero di aperture e al valore ottenuto. Poco tempo con molti risultati indica efficienza, molto tempo potrebbe indicare difficoltà di navigazione o utilizzo molto approfondito.',
          'examples': [
            '5 ore in 30 giorni = ~10 minuti al giorno (uso regolare)',
            '20 ore in 7 giorni = utilizzo molto intensivo',
            '2 ore in 30 giorni = utilizzo leggero ma può essere ottimale'
          ],
          'tips': 'Il tempo "giusto" dipende dai tuoi obiettivi. Se ottieni valore in poco tempo, sei efficiente. Se passi molto tempo ma non trovi quello che cerchi, potresti migliorare l\'organizzazione.'
        };
        
      // STATISTICHE AVANZATE
      case 'sessions_total':
        return {
          'icon': Icons.access_time,
          'color': Colors.indigo,
          'description': 'Numero totale di sessioni di utilizzo app. Una sessione è un periodo di utilizzo continuo dell\'app, dall\'apertura alla chiusura o inattività prolungata.',
          'interpretation': 'Molte sessioni brevi possono indicare utilizzo rapido ed efficiente. Poche sessioni lunghe possono indicare un uso più contemplativo e approfondito. Il numero ideale dipende dal tuo stile.',
          'examples': [
            '50 sessioni in un mese = ~1.6 sessioni al giorno (utilizzo costante)',
            '10 sessioni lunghe = utilizzo intensivo ma sporadico',
            'Molte sessioni da 1-2 minuti = utilizzo rapido per consultazioni veloci'
          ],
          'tips': 'Confronta con la durata media delle sessioni. Se hai molte sessioni molto brevi, potresti aver bisogno di migliorare l\'organizzazione per trovare più rapidamente ciò che cerchi.'
        };
        
      case 'content_interactions':
        return {
          'icon': Icons.touch_app,
          'color': Colors.green,
          'description': 'Numero di contenuti con cui hai interagito almeno una volta dopo averli salvati. Include aperture, visualizzazioni e qualsiasi forma di engagement.',
          'interpretation': 'Un alto numero indica che trovi valore nei contenuti salvati. Un numero basso rispetto ai contenuti totali può suggerire difficoltà nel ritrovare o scarsa rilevanza dei contenuti salvati.',
          'examples': [
            '80 interazioni su 100 contenuti = 80% di engagement (eccellente)',
            '30 interazioni su 200 contenuti = 15% di engagement (da migliorare)',
            'Interazioni multiple sugli stessi contenuti = alta qualità dei contenuti'
          ],
          'tips': 'Punta a un tasso di interazione del 50%+. Se è più basso, considera di essere più selettivo nel salvare contenuti o di migliorare l\'organizzazione.'
        };
        
      case 'org_efficiency':
        return {
          'icon': Icons.architecture,
          'color': Colors.purple,
          'description': 'Score complessivo dell\'efficienza della tua organizzazione in cartelle. Considera profondità, utilizzo, distribuzione e facilità di navigazione.',
          'interpretation': 'Un punteggio alto (70%+) indica un\'organizzazione ben strutturata e utilizzata. Un punteggio basso può indicare cartelle troppo profonde, sottoutilizzate o mal distribuite.',
          'examples': [
            '85% = Organizzazione ottimale con cartelle ben utilizzate',
            '45% = Molte cartelle vuote o struttura troppo complessa',
            '60% = Buona base ma può essere migliorata'
          ],
          'tips': 'Per migliorare: rimuovi cartelle vuote, evita nidificazioni troppo profonde (>3 livelli), e assicurati che ogni cartella abbia uno scopo chiaro.'
        };
        
      case 'insights_generated':
        return {
          'icon': Icons.info,
          'color': Colors.grey,
          'description': 'Informazioni non disponibili per questa statistica.',
          'interpretation': '—',
          'examples': ['N/A'],
        };
        
      case 'avg_session_time':
        return {
          'icon': Icons.timer,
          'color': Colors.blue,
          'description': 'Durata media delle tue sessioni di utilizzo dell\'app. Calcolata dal momento dell\'apertura fino alla chiusura o inattività prolungata.',
          'interpretation': 'Sessioni brevi (1-3 min) indicano utilizzo efficiente per compiti specifici. Sessioni lunghe (5+ min) possono indicare navigazione esplorativa o difficoltà nel trovare contenuti.',
          'examples': [
            '2 minuti = Utilizzo mirato ed efficiente',
            '8 minuti = Navigazione approfondita o ricerca complessa',
            '30 secondi = Possibili problemi di navigazione o contenuti irrilevanti'
          ],
          'tips': 'La durata ideale dipende dai tuoi obiettivi. Se cerchi rapidità, punta a 1-3 minuti. Se vuoi esplorare e organizzare, 5-10 minuti sono normali.'
        };
        
      case 'revisitation_rate':
        return {
          'icon': Icons.info,
          'color': Colors.grey,
          'description': 'Informazioni non disponibili per questa statistica.',
          'interpretation': '—',
          'examples': ['N/A'],
        };
        
      case 'abandonment_rate':
        return {
          'icon': Icons.info,
          'color': Colors.grey,
          'description': 'Informazioni non disponibili per questa statistica.',
          'interpretation': '—',
          'examples': ['N/A'],
        };
        
      case 'consistency_score':
        return {
          'icon': Icons.info,
          'color': Colors.grey,
          'description': 'Informazioni non disponibili per questa statistica.',
          'interpretation': '—',
          'examples': ['N/A'],
        };
        
      case 'avg_folder_depth':
        return {
          'icon': Icons.height,
          'color': Colors.purple,
          'description': 'Profondità media del tuo albero di cartelle. Misura quanti livelli di nidificazione usi mediamente per organizzare i contenuti.',
          'interpretation': 'Profondità moderata (2-3 livelli) è ottimale per la navigazione. Troppo superficiale (<2) può creare disordine, troppo profonda (>4) rende difficile trovare contenuti.',
          'examples': [
            '2.5 livelli = Struttura equilibrata e navigabile',
            '1.2 livelli = Organizzazione troppo piatta, possibile disordine',
            '4.8 livelli = Troppo complessa, difficile da navigare'
          ],
          'tips': 'Punta a 2-3 livelli. Usa la regola "3 click per arrivare ovunque": ogni contenuto dovrebbe essere raggiungibile in massimo 3 passaggi.'
        };
        
      case 'total_folders':
        return {
          'icon': Icons.folder,
          'color': Colors.blue,
          'description': 'Numero totale di cartelle create per organizzare i contenuti. Include cartelle attive, vuote e quelle con sottocartelle.',
          'interpretation': 'Il numero ottimale dipende dai tuoi contenuti. Troppo poche cartelle creano disordine, troppe creano complessità. La regola generale è 5-15 cartelle principali.',
          'examples': [
            '8 cartelle principali = Buon equilibrio per la maggior parte degli utenti',
            '25+ cartelle = Possibile over-organizzazione',
            '3 cartelle = Troppo semplice per contenuti diversificati'
          ],
          'tips': 'Inizia con 5-7 categorie principali (Lavoro, Personale, Hobby, etc.) e crea sottocartelle solo quando necessario. Elimina cartelle vuote regolarmente.'
        };
        
      case 'folders_utilization':
        return {
          'icon': Icons.info,
          'color': Colors.grey,
          'description': 'Informazioni non disponibili per questa statistica.',
          'interpretation': '—',
          'examples': ['N/A'],
        };
        
      case 'org_efficiency_detail':
        return {
          'icon': Icons.info,
          'color': Colors.grey,
          'description': 'Informazioni non disponibili per questa statistica.',
          'interpretation': '—',
          'examples': ['N/A'],
        };
        
      case 'content_efficiency':
        return {
          'icon': Icons.info,
          'color': Colors.grey,
          'description': 'Informazioni non disponibili per questa statistica.',
          'interpretation': '—',
          'examples': ['N/A'],
        };
        
      case 'never_opened':
        return {
          'icon': Icons.close,
          'color': Colors.red,
          'description': 'Numero di contenuti salvati ma mai aperti nemmeno una volta. Rappresenta il "peso morto" della tua collezione.',
          'interpretation': 'Un numero alto indica accumulo di contenuti inutili. Possono essere contenuti salvati impulsivamente, non più rilevanti o semplicemente dimenticati.',
          'examples': [
            '5 su 50 contenuti = 10% mai aperti (accettabile)',
            '40 su 60 contenuti = 67% mai aperti (problematico)',
            '0 contenuti mai aperti = Eccellente utilizzo'
          ],
          'tips': 'Rivedi regolarmente questi contenuti. Se non li hai aperti in 30+ giorni, probabilmente puoi eliminarli. Usa la funzione di pulizia automatica se disponibile.'
        };
        
      case 'high_engagement':
        return {
          'icon': Icons.info,
          'color': Colors.grey,
          'description': 'Informazioni non disponibili per questa statistica.',
          'interpretation': '—',
          'examples': ['N/A'],
        };
        
      case 'duplicate_content':
        return {
          'icon': Icons.content_copy,
          'color': Colors.grey,
          'description': 'Contenuti duplicati o molto simili salvati più volte. Include URL identici, contenuti dallo stesso autore o argomenti molto simili.',
          'interpretation': 'I duplicati occupano spazio e creano confusione. Un numero alto può indicare salvataggio frettoloso o mancanza di controllo prima di salvare.',
          'examples': [
            '2 duplicati su 100 contenuti = 2% (ottimo controllo)',
            '15 duplicati su 80 contenuti = 19% (rivedi il processo di salvataggio)',
            '0 duplicati = Eccellente controllo pre-salvataggio'
          ],
          'tips': 'Prima di salvare, cerca rapidamente se hai già contenuti simili. Usa funzioni di ricerca per identificare e rimuovere i duplicati esistenti.'
        };
        
      default:
        return {
          'icon': Icons.info,
          'color': Colors.grey,
          'description': 'Informazioni non disponibili per questa statistica.',
          'interpretation': 'Contatta il supporto per maggiori dettagli.',
          'examples': ['N/A'],
        };
    }
  }

  // ============================================================================
  // METODI AZIONI E DIALOG (MANTENUTI + NUOVI)
  // ============================================================================

  void _showCreateFolderDialog() {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkTheme ? Colors.grey.shade900 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Nuova Cartella',
          style: TextStyle(
            color: widget.isDarkTheme ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Crea una nuova cartella dalla pagina statistiche',
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.grey.shade300 : Colors.black54,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: controller,
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.white : Colors.black87,
              ),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Nome cartella',
                hintStyle: TextStyle(
                  color: widget.isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                filled: true,
                fillColor: widget.isDarkTheme ? Colors.grey.shade800 : Colors.grey.shade100,
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
            child: Text(
              'Annulla',
              style: TextStyle(
                color: widget.isDarkTheme ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                Navigator.popUntil(context, (route) => route.isFirst);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Torna alla home per creare la cartella "${controller.text.trim()}"'),
                    backgroundColor: Colors.blue,
                    action: SnackBarAction(
                      label: 'OK',
                      textColor: Colors.white,
                      onPressed: () {},
                    ),
                  ),
                );
              }
            },
            child: Text(
              'Crea',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _exportData() {
    try {
      final data = _analytics.exportData();
      print('Export dati base: $data');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dati base esportati (vedi console debug)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore esportazione: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _exportAdvancedData() {
    try {
      final data = _advancedAnalytics.exportAdvancedData();
      print('Export dati avanzati: $data');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dati avanzati esportati (vedi console debug)'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore esportazione avanzata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showInsightsDialog() {
    if (_advancedStats == null || _advancedStats!.insights.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.lightbulb, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'Tutti gli Insight',
              style: TextStyle(color: Colors.black87, fontSize: 18),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: _advancedStats!.insights.length,
            itemBuilder: (context, index) {
              final insight = _advancedStats!.insights[index];
              return Container(
                margin: EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getInsightTypeColor(insight.type).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _getInsightTypeColor(insight.type).withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getInsightTypeIcon(insight.type),
                          color: _getInsightTypeColor(insight.type),
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            insight.title,
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getConfidenceColor(insight.confidence).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${(insight.confidence * 100).toInt()}%',
                            style: TextStyle(
                              color: _getConfidenceColor(insight.confidence),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      insight.description,
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    if (insight.isActionable) ...[
                      SizedBox(height: 6),
                      Text(
                        '💡 ${insight.recommendation}',
                        style: TextStyle(
                          color: _getInsightTypeColor(insight.type),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Chiudi', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancella Dati Analytics', style: TextStyle(color: Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Seleziona quali dati cancellare:',
              style: TextStyle(color: Colors.black54),
            ),
            SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _analytics.clearAllData();
                      Navigator.pop(context);
                      _loadStats();
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Dati base cancellati'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
                    icon: Icon(Icons.bar_chart, size: 16),
                    label: Text('Base', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.withOpacity(0.1),
                      foregroundColor: Colors.orange,
                      elevation: 0,
                    ),
                  ),
                ),
                
                SizedBox(width: 8),
                
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _advancedAnalytics.clearAllAdvancedData();
                      Navigator.pop(context);
                      _loadStats();
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Dati avanzati cancellati'),
                          backgroundColor: Colors.blue,
                        ),
                      );
                    },
                    icon: Icon(Icons.analytics, size: 16),
                    label: Text('Avanzati', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      foregroundColor: Colors.blue,
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 8),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _analytics.clearAllData();
                  await _advancedAnalytics.clearAllAdvancedData();
                  Navigator.pop(context);
                  _loadStats();
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Tutti i dati analytics cancellati'),
                      backgroundColor: Colors.red,
                    ),
                  );
                },
                icon: Icon(Icons.delete_forever, size: 16),
                label: Text('Cancella Tutto', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.1),
                  foregroundColor: Colors.red,
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Map<String, int> _topNonSocialSites(Map<String, int> domainCounts, {int limit = 3}) {
    final filtered = domainCounts.entries
        .where((e) => !_isKnownSocialDomain(e.key.toLowerCase()))
        .take(limit)
        .toList();
    return Map.fromEntries(filtered);
  }

  bool _isKnownSocialDomain(String domain) {
    final socials = [
      'instagram', 'facebook', 'twitter', 'x.com', 'youtube', 'youtu.be',
      'tiktok', 'linkedin', 'pinterest', 'reddit', 'github'
    ];
    return socials.any((s) => domain.contains(s));
  }

  // NUOVO: Converte il dominio in nome friendly del social network
  String _getSocialNetworkName(String domain) {
    final domainLower = domain.toLowerCase();
    
    if (domainLower.contains('instagram')) return 'Instagram';
    if (domainLower.contains('facebook') || domainLower.contains('fb.')) return 'Facebook';
    if (domainLower.contains('twitter') || domainLower.contains('x.com')) return 'X (Twitter)';
    if (domainLower.contains('youtube') || domainLower.contains('youtu.be')) return 'YouTube';
    if (domainLower.contains('tiktok')) return 'TikTok';
    if (domainLower.contains('linkedin')) return 'LinkedIn';
    if (domainLower.contains('pinterest')) return 'Pinterest';
    if (domainLower.contains('reddit')) return 'Reddit';
    if (domainLower.contains('github')) return 'GitHub';
    
    // Fallback: capitalizza il dominio
    return domain.split('.').first.substring(0, 1).toUpperCase() + 
           domain.split('.').first.substring(1);
  }

  // NUOVO: Calcola il tempo medio per sessione (con secondi)
  String _calculateAverageTime() {
    if (_stats == null || _stats!.totalAppOpens == 0) return '0m 0s';
    
    final totalSeconds = _stats!.totalTimeInApp.inSeconds;
    final averageSeconds = totalSeconds / _stats!.totalAppOpens;
    
    if (averageSeconds < 60) {
      // Solo secondi
      return '${averageSeconds.toStringAsFixed(0)}s';
    } else if (averageSeconds < 3600) {
      // Minuti e secondi
      final minutes = averageSeconds ~/ 60;
      final seconds = (averageSeconds % 60).toStringAsFixed(0);
      return '${minutes}m ${seconds}s';
    } else {
      // Ore, minuti e secondi
      final hours = averageSeconds ~/ 3600;
      final remainingSeconds = averageSeconds % 3600;
      final minutes = remainingSeconds ~/ 60;
      final seconds = (remainingSeconds % 60).toStringAsFixed(0);
      return '${hours}h ${minutes}m ${seconds}s';
    }
  }

  // NUOVO: Calcola le aperture medie settimanali
  String _calculateWeeklyAverageOpens() {
    if (_stats == null || _stats!.totalAppOpens == 0) return '0';
    
    // Calcola quante settimane sono passate dalla prima apertura
    final now = DateTime.now();
    final daysSinceFirstUse = now.difference(_stats!.firstUse).inDays;
    final weeksSinceFirstUse = daysSinceFirstUse / 7;
    
    // Se è passata meno di una settimana, usa almeno 1 settimana per il calcolo
    final weeks = weeksSinceFirstUse < 1 ? 1 : weeksSinceFirstUse;
    
    // Calcola la media
    final weeklyAverage = _stats!.totalAppOpens / weeks;
    
    return weeklyAverage.toStringAsFixed(1);
  }

  // NUOVO: Calcola le ricerche medie settimanali
  String _calculateWeeklyAverageSearches() {
    if (_stats == null || _stats!.totalSearches == 0) return '0';
    
    // Calcola quante settimane sono passate dalla prima apertura
    final now = DateTime.now();
    final daysSinceFirstUse = now.difference(_stats!.firstUse).inDays;
    final weeksSinceFirstUse = daysSinceFirstUse / 7;
    
    // Se è passata meno di una settimana, usa almeno 1 settimana per il calcolo
    final weeks = weeksSinceFirstUse < 1 ? 1 : weeksSinceFirstUse;
    
    // Calcola la media
    final weeklyAverage = _stats!.totalSearches / weeks;
    
    return weeklyAverage.toStringAsFixed(1);
  }

  // Risolve l'URL originale dai link di condivisione di Google
  Future<String?> _resolveGoogleShareUrl(String url) async {
    try {
      // METODO 1: Prova prima a estrarre l'URL dal parametro query
      final uri = Uri.parse(url);
      if (uri.queryParameters.containsKey('url')) {
        final extractedUrl = uri.queryParameters['url'];
        if (extractedUrl != null && extractedUrl.isNotEmpty) {
          print('DEBUG: URL estratto da parametro query: $extractedUrl');
          return extractedUrl;
        }
      }
      
      // METODO 2: Segui il redirect HTTP
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ).timeout(Duration(seconds: 5));

        // Controlla se c'è stato un redirect
        if (response.request?.url != null) {
          final finalUrl = response.request!.url.toString();
          if (finalUrl != url && !finalUrl.contains('share.google.com')) {
            print('DEBUG: URL risolto tramite redirect: $finalUrl');
            return finalUrl;
          }
        }
        
        // METODO 3: Cerca nell'HTML
        if (response.statusCode == 200) {
          final html = response.body;
          
          // Cerca meta refresh (pattern semplificato)
          final metaRefresh = RegExp(r'url=(https?://[^\s<>"]+)', caseSensitive: false);
          final refreshMatch = metaRefresh.firstMatch(html);
          if (refreshMatch != null && refreshMatch.group(1) != null) {
            final foundUrl = refreshMatch.group(1)!;
            if (!foundUrl.contains('share.google.com')) {
              print('DEBUG: URL trovato in meta refresh: $foundUrl');
              return foundUrl;
            }
          }
        }
      } catch (e) {
        print('DEBUG: Errore nella richiesta HTTP: $e');
      }
    } catch (e) {
      print('DEBUG: Errore generale risoluzione URL: $e');
    }
    
    return null;
  }

  // NUOVO: Calcola statistiche social network da post reali (non eventi storici)
  Future<Map<String, int>> _getTopSocialNetworks({int limit = 5}) async {
    if (_stats == null) return {};
    
    try {
      // Accedi direttamente ai post reali tramite FolderService
      final allPosts = _folderService.allPosts;
      print('DEBUG: Trovati ${allPosts.length} post per analisi social network');
      
      final socialCounts = <String, int>{};
      
      // Analizza tutti i post per identificare i social network
      for (var post in allPosts) {
        try {
          var url = post.url;
          
          // Risolvi l'URL se è un link di condivisione
          if (url.contains('share.google.com')) {
            try {
              final resolvedUrl = await _resolveGoogleShareUrl(url);
              if (resolvedUrl != null && resolvedUrl != url) {
                url = resolvedUrl;
              }
            } catch (e) {
              print('DEBUG: Errore risoluzione URL Google: $e');
            }
          }
          
          final uri = Uri.parse(url);
          var domain = uri.host.toLowerCase();
          
          // Estrai il dominio principale
          if (domain.contains('.')) {
            final parts = domain.split('.');
            if (parts.length >= 3) {
              domain = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
            }
          }
          
          // SOLO i social network noti
          if (_isKnownSocialDomain(domain)) {
            // Usa il nome friendly del social network
            final socialName = _getSocialNetworkName(domain);
            socialCounts[socialName] = (socialCounts[socialName] ?? 0) + 1;
            print('DEBUG: Post da $socialName (${post.url})');
          }
        } catch (e) {
          print('DEBUG: Errore parsing URL ${post.url}: $e');
        }
      }
      
      print('DEBUG: Social network trovati: ${socialCounts.keys.toList()}');
      
      // Ordina per frequenza e prendi i primi 5
      final sortedSocials = socialCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      final result = Map.fromEntries(sortedSocials.take(limit));
      print('DEBUG: Top social network: ${result.entries.map((e) => '${e.key}: ${e.value}').toList()}');
      
      return result;
      
    } catch (e) {
      print('DEBUG: Errore nel calcolo social network: $e');
      return {};
    }
  }

  Future<Map<String, int>> _getTopWebsites({int limit = 5}) async {
    if (_stats == null) return {};
    
    try {
      // Accedi direttamente ai post reali tramite FolderService
      final allPosts = _folderService.allPosts;
      print('DEBUG: Trovati ${allPosts.length} post per analisi siti web');
      
      final domainCounts = <String, int>{};
      
      // Analizza tutti i post per estrarre i domini
      for (var post in allPosts) {
        try {
          var url = post.url;
          var domain = '';
          
          // Se è un link di condivisione di Google, prova a estrarre l'URL originale
          if (url.contains('share.google.com')) {
            print('DEBUG: Trovato link di condivisione Google: $url');
            
            try {
              // Usa lo stesso approccio di UrlMetadataService per risolvere l'URL
              final resolvedUrl = await _resolveGoogleShareUrl(url);
              if (resolvedUrl != null && resolvedUrl != url) {
                print('DEBUG: URL originale risolto: $resolvedUrl');
                url = resolvedUrl;
              }
            } catch (e) {
              print('DEBUG: Errore risoluzione URL Google: $e');
            }
          }
          
          final uri = Uri.parse(url);
          domain = uri.host.toLowerCase();
          
          // Estrai il dominio principale (es. share.google.com -> google.com)
          if (domain.contains('.')) {
            final parts = domain.split('.');
            if (parts.length >= 3) {
              // Per domini con 3+ parti (es. share.google.com), prendi le ultime due
              domain = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
            } else if (parts.length == 2) {
              // Per domini con 2 parti (es. google.com), mantieni così
              domain = domain;
            }
          }
          
          print('DEBUG: URL finale: $url -> Dominio: $domain');
          
          // Escludi i social network noti
          if (!_isKnownSocialDomain(domain)) {
            domainCounts[domain] = (domainCounts[domain] ?? 0) + 1;
          }
        } catch (e) {
          print('DEBUG: Errore parsing URL ${post.url}: $e');
        }
      }
      
      print('DEBUG: Domini trovati: ${domainCounts.keys.toList()}');
      
      // Ordina per frequenza e prendi i primi 5
      final sortedDomains = domainCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      final result = Map.fromEntries(sortedDomains.take(limit));
      print('DEBUG: Top siti web: ${result.entries.map((e) => '${e.key}: ${e.value}').toList()}');
      
      return result;
      
    } catch (e) {
      print('DEBUG: Errore nel calcolo siti web: $e');
      return {};
    }
  }

  // NUOVO: Calcola i top 10 hashtag più utilizzati
  Future<Map<String, int>> _getTopHashtags({int limit = 10}) async {
    if (_stats == null) return {};
    
    try {
      // Accedi direttamente ai post reali tramite FolderService
      final allPosts = _folderService.allPosts;
      print('DEBUG: Trovati ${allPosts.length} post per analisi hashtag');
      
      final hashtagCounts = <String, int>{};
      
      // Analizza tutti i post per estrarre gli hashtag
      for (var post in allPosts) {
        try {
          // Ogni post ha una lista di tag
          for (var tag in post.tags) {
            final cleanTag = tag.trim().toLowerCase();
            if (cleanTag.isNotEmpty) {
              hashtagCounts[cleanTag] = (hashtagCounts[cleanTag] ?? 0) + 1;
            }
          }
        } catch (e) {
          print('DEBUG: Errore estrazione tag dal post ${post.id}: $e');
        }
      }
      
      print('DEBUG: Hashtag trovati: ${hashtagCounts.length} unici');
      
      // Ordina per frequenza e prendi i primi 10
      final sortedHashtags = hashtagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      final result = Map.fromEntries(sortedHashtags.take(limit));
      print('DEBUG: Top 10 hashtag: ${result.entries.map((e) => '#${e.key}: ${e.value}').toList()}');
      
      return result;
      
    } catch (e) {
      print('DEBUG: Errore nel calcolo hashtag: $e');
      return {};
    }
  }
}