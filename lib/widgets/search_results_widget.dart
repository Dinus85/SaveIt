import 'package:flutter/material.dart';
import 'package:savein/models/folder.dart';
import 'package:savein/models.dart';
import '../utils/theme_helpers.dart';
import '../services/sharing_service.dart';
import '../services/folder_service_models.dart';
import 'post_preview_image.dart';

// Widget condiviso per i risultati di ricerca
class SearchResultsWidget extends StatelessWidget {
  final List<SearchResult> searchResults;
  final bool isDarkTheme;
  final Function(SearchResult) onResultTap;
  final Future<void> Function()? onRefresh;

  const SearchResultsWidget({
    Key? key,
    required this.searchResults,
    required this.isDarkTheme,
    required this.onResultTap,
    this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(isDarkTheme);

    if (searchResults.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh ?? (() async {}),
        color: Colors.blue,
        backgroundColor: isDarkTheme ? Colors.grey[800] : Colors.white,
        child: SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Container(
            height: MediaQuery.of(context).size.height - 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, color: Colors.grey, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Nessun risultato trovato',
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Prova a cercare per #hashtag o parole chiave',
                    style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh ?? (() async {}),
      color: Colors.blue,
      backgroundColor: isDarkTheme ? Colors.grey[800] : Colors.white,
      child: ListView.builder(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 16),
        itemCount: searchResults.length,
        itemBuilder: (context, index) {
          final result = searchResults[index];
          return _buildSearchResultCard(result, themeColors);
        },
      ),
    );
  }

  Widget _buildSearchResultCard(SearchResult result, ThemeColors themeColors) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: ThemeHelpers.getCardDecoration(isDarkTheme),
      child: InkWell(
        onTap: () => onResultTap(result),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              result.type == 'post' && result.post != null
                  ? _buildPostThumbnail(result.post!, themeColors)
                  : Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: result.type == 'folder'
                            ? (result.color ?? Colors.blue)
                            : Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        result.type == 'folder' ? Icons.folder : Icons.article,
                        color: result.type == 'folder'
                            ? Colors.black87
                            : Colors.blue,
                        size: 24,
                      ),
                    ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: TextStyle(
                        color: themeColors.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      result.subtitle,
                      style: TextStyle(
                          color: themeColors.subtitleColor, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Mostra il sito web per i post
                    if (result.type == 'post' && result.post != null) ...[
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.language,
                              color: themeColors.hintColor, size: 12),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _extractDomain(result.post!.url),
                              style: TextStyle(
                                color: themeColors.hintColor,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostThumbnail(MockPost post, ThemeColors themeColors) {
    final hasPreview = post.imageUrl?.isNotEmpty == true ||
        post.previewStorageUrl?.isNotEmpty == true;

    if (hasPreview) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: PostPreviewImage(
            postId: post.id,
            postUrl: post.url,
            imageUrl: post.imageUrl,
            remoteImageUrl: post.previewStorageUrl,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return _buildFallbackThumbnail(post, themeColors);
  }

  Widget _buildFallbackThumbnail(MockPost post, ThemeColors themeColors) {
    final domain = _extractDomain(post.url);
    final thumbnailColor = _getDomainColor(domain);
    final thumbnailIcon = _getDomainIcon(domain);

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: thumbnailColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: thumbnailColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Icon(
        thumbnailIcon,
        color: thumbnailColor,
        size: 20,
      ),
    );
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (e) {
      return 'Link';
    }
  }

  Color _getDomainColor(String domain) {
    final colors = [
      Colors.red.shade500,
      Colors.blue.shade500,
      Colors.green.shade500,
      Colors.orange.shade500,
      Colors.purple.shade500,
      Colors.teal.shade500,
      Colors.indigo.shade500,
      Colors.pink.shade500,
    ];

    final hash = domain.hashCode;
    return colors[hash.abs() % colors.length];
  }

  IconData _getDomainIcon(String domain) {
    if (domain.contains('instagram')) return Icons.camera_alt;
    if (domain.contains('youtube')) return Icons.play_circle;
    if (domain.contains('facebook')) return Icons.people;
    if (domain.contains('twitter')) return Icons.chat;
    if (domain.contains('pinterest')) return Icons.push_pin;
    if (domain.contains('linkedin')) return Icons.business;
    if (domain.contains('tiktok')) return Icons.music_note;
    return Icons.language;
  }
}
