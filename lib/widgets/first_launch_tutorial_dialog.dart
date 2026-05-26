import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SaveInFirstLaunchTutorial {
  static const String seenKey = 'savein_first_launch_tutorial_seen_v1';

  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(seenKey) == true) return;
    if (!context.mounted) return;

    await show(context, markSeenOnClose: true);
  }

  static Future<void> show(
    BuildContext context, {
    bool markSeenOnClose = false,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SaveInFirstLaunchTutorialDialog(
        onClose: () async {
          if (!markSeenOnClose) return;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(seenKey, true);
        },
      ),
    );
  }
}

class SaveInFirstLaunchTutorialDialog extends StatefulWidget {
  final Future<void> Function() onClose;

  const SaveInFirstLaunchTutorialDialog({
    super.key,
    required this.onClose,
  });

  @override
  State<SaveInFirstLaunchTutorialDialog> createState() =>
      _SaveInFirstLaunchTutorialDialogState();
}

class _SaveInFirstLaunchTutorialDialogState
    extends State<SaveInFirstLaunchTutorialDialog> {
  final PageController _controller = PageController();
  int _index = 0;
  bool _closing = false;

  static const List<_TutorialSlideData> _slides = [
    _TutorialSlideData(
      illustration: _TutorialIllustrationType.folders,
      title: 'Crea cartelle e sottocartelle',
      message:
          'Organizza le idee in modo ordinato: ad esempio “Fai da te” con Idee casa, Giardino, Riciclo e Strumenti.',
      color: Color(0xFF2C7A7B),
    ),
    _TutorialSlideData(
      illustration: _TutorialIllustrationType.savePost,
      title: 'Salva i post dove vuoi',
      message:
          'Quando trovi un contenuto utile, salvalo subito nella cartella giusta per ritrovarlo facilmente.',
      color: Color(0xFF7C3AED),
    ),
    _TutorialSlideData(
      illustration: _TutorialIllustrationType.tagsSearch,
      title: 'Aggiungi tag e cerca',
      message:
          'Usa tag come “legno”, “regalo” o “ricetta” e ritrova tutto dalla barra di ricerca.',
      color: Color(0xFF2563EB),
    ),
    _TutorialSlideData(
      illustration: _TutorialIllustrationType.reminder,
      title: 'Aggiungi un reminder',
      message:
          'Imposta un promemoria su una cartella, per esempio “Natale”, e SaveIn ti ricorda quando riaprirla.',
      color: Color(0xFFEA580C),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await widget.onClose();
    if (mounted) Navigator.of(context).pop();
  }

  void _goTo(int page) {
    if (page < 0 || page >= _slides.length) return;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final maxHeight = screen.height * 0.78;
    final maxWidth = screen.width * 0.88;
    var width = maxHeight * 9 / 16;
    if (width > maxWidth) width = maxWidth;
    final height = width * 16 / 9;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          elevation: 18,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  return _TutorialSlide(slide: _slides[index]);
                },
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  tooltip: 'Chiudi tutorial',
                  onPressed: _close,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.08),
                  ),
                  icon: const Icon(Icons.close, color: Color(0xFF111827)),
                ),
              ),
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    tooltip: 'Slide precedente',
                    onPressed: _index == 0 ? null : () => _goTo(_index - 1),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.9),
                      disabledBackgroundColor: Colors.white.withOpacity(0.35),
                    ),
                    icon: const Icon(Icons.chevron_left, size: 34),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    tooltip: 'Slide successiva',
                    onPressed: _index == _slides.length - 1
                        ? null
                        : () => _goTo(_index + 1),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.9),
                      disabledBackgroundColor: Colors.white.withOpacity(0.35),
                    ),
                    icon: const Icon(Icons.chevron_right, size: 34),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 22,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _slides.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: i == _index ? 22 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: i == _index
                                ? _slides[_index].color
                                : const Color(0xFFD1D5DB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    if (_index == _slides.length - 1) ...[
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _close,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2C7A7B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 34,
                            vertical: 14,
                          ),
                        ),
                        child: const Text('Chiudi'),
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
}

class _TutorialSlideData {
  final _TutorialIllustrationType illustration;
  final String title;
  final String message;
  final Color color;

  const _TutorialSlideData({
    required this.illustration,
    required this.title,
    required this.message,
    required this.color,
  });
}

enum _TutorialIllustrationType { folders, savePost, tagsSearch, reminder }

class _TutorialSlide extends StatelessWidget {
  final _TutorialSlideData slide;

  const _TutorialSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(34, 62, 34, 116),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            slide.color.withOpacity(0.18),
            Colors.white,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TutorialIllustration(slide: slide),
          const SizedBox(height: 28),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            slide.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 16,
              height: 1.42,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialIllustration extends StatelessWidget {
  final _TutorialSlideData slide;

  const _TutorialIllustration({required this.slide});

  @override
  Widget build(BuildContext context) {
    switch (slide.illustration) {
      case _TutorialIllustrationType.folders:
        return _FoldersIllustration(color: slide.color);
      case _TutorialIllustrationType.savePost:
        return _SavePostIllustration(color: slide.color);
      case _TutorialIllustrationType.tagsSearch:
        return _TagsSearchIllustration(color: slide.color);
      case _TutorialIllustrationType.reminder:
        return _ReminderIllustration(color: slide.color);
    }
  }
}

class _FoldersIllustration extends StatelessWidget {
  final Color color;

  const _FoldersIllustration({required this.color});

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FolderPill(
            color: color,
            icon: Icons.folder,
            label: 'Fai da te',
            large: true,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _SmallFolder(label: 'Idee casa'),
              _SmallFolder(label: 'Giardino'),
              _SmallFolder(label: 'Riciclo'),
              _SmallFolder(label: 'Strumenti'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavePostIllustration extends StatelessWidget {
  final Color color;

  const _SavePostIllustration({required this.color});

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.article_outlined, color: color),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Come restaurare un mobile',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Post salvato',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.bookmark_added, color: color),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Icon(Icons.arrow_downward_rounded, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          _FolderPill(
            color: color,
            icon: Icons.folder,
            label: 'Fai da te / Idee casa',
          ),
        ],
      ),
    );
  }
}

class _TagsSearchIllustration extends StatelessWidget {
  final Color color;

  const _TagsSearchIllustration({required this.color});

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.24)),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: color),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Cerca: legno',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TagChip(color: color, label: 'legno'),
              _TagChip(color: color, label: 'regalo'),
              _TagChip(color: color, label: 'ricetta'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.sell_outlined, color: color),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Mensola in legno salvata',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderIllustration extends StatelessWidget {
  final Color color;

  const _ReminderIllustration({required this.color});

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FolderPill(
            color: color,
            icon: Icons.folder_special,
            label: 'Natale',
            large: true,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.notifications_active, color: color),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reminder attivo',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '1 Dicembre alle 09:00',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
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
    );
  }
}

class _TagChip extends StatelessWidget {
  final Color color;
  final String label;

  const _TagChip({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tag, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _IllustrationFrame extends StatelessWidget {
  final Color color;
  final Widget child;

  const _IllustrationFrame({
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: child,
    );
  }
}

class _FolderPill extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final bool large;

  const _FolderPill({
    required this.color,
    required this.icon,
    required this.label,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 12,
        vertical: large ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: large ? 24 : 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: large ? 18 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallFolder extends StatelessWidget {
  final String label;

  const _SmallFolder({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_outlined, color: Colors.amber.shade700, size: 17),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
