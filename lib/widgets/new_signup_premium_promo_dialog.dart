import 'package:flutter/material.dart';

class NewSignupPremiumPromoDialog extends StatefulWidget {
  final int durationDays;
  final String priceAfterTrial;

  const NewSignupPremiumPromoDialog({
    super.key,
    required this.durationDays,
    required this.priceAfterTrial,
  });

  @override
  State<NewSignupPremiumPromoDialog> createState() =>
      _NewSignupPremiumPromoDialogState();
}

class _NewSignupPremiumPromoDialogState
    extends State<NewSignupPremiumPromoDialog> {
  final PageController _controller = PageController();
  int _index = 0;

  late final List<_PromoSlideData> _slides = [
    _PromoSlideData(
      illustration: _PromoIllustrationType.gift,
      title: '🎁 Un mese Premium gratis',
      message:
          'Attiva la prova e usa SaveIn! Premium per ${widget.durationDays} giorni senza pagare. Dal secondo mese, se vorrai continuare, il piano costa €${widget.priceAfterTrial} al mese ✨',
      color: const Color(0xFF2563EB),
      highlights: const [
        'Premium attivo subito',
        'Scadenza visibile nell’Account',
        'Nessun limite Free durante la prova',
      ],
    ),
    const _PromoSlideData(
      illustration: _PromoIllustrationType.folders,
      title: '📁 Organizza senza limiti',
      message:
          'Crea una struttura più profonda e ordinata: progetti, sottocartelle e dettagli sempre a portata di mano, senza dover comprimere tutto in pochi spazi.',
      color: Color(0xFF2C7A7B),
      highlights: [
        'Più livelli di cartelle',
        'Più ordine nei progetti personali',
        'Meno confusione quando salvi tanti contenuti',
      ],
    ),
    const _PromoSlideData(
      illustration: _PromoIllustrationType.tags,
      title: '🏷️ Ritrova tutto più velocemente',
      message:
          'Aggiungi tag manuali ai contenuti salvati e rendi ogni ricerca più precisa. Ideale quando ricordi l’argomento, ma non la cartella dove hai salvato.',
      color: Color(0xFF7C3AED),
      highlights: [
        'Tag personalizzati',
        'Ricerca più precisa',
        'Contenuti importanti ritrovati prima',
      ],
    ),
    const _PromoSlideData(
      illustration: _PromoIllustrationType.premium,
      title: '🚀 Niente pubblicità, più fluidità',
      message:
          'Usa SaveIn! con un’esperienza più pulita, continua e piacevole. Meno interruzioni, più concentrazione sui contenuti che vuoi salvare e ritrovare.',
      color: Color(0xFFEA580C),
      highlights: [
        'Niente annunci interstitial',
        'Esperienza più fluida',
        'Attivazione immediata della prova',
      ],
      showActivateButton: true,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close(bool accepted) {
    Navigator.of(context).pop(accepted);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final maxHeight = screen.height * 0.78;
    final maxWidth = screen.width * 0.88;
    var width = maxHeight * 10.5 / 16;
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
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFF111827)),
            child: IconTheme(
              data: const IconThemeData(color: Color(0xFF111827)),
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) {
                      return _PromoSlide(slide: _slides[index]);
                    },
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: IconButton(
                      tooltip: 'Chiudi promo',
                      onPressed: () => _close(false),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.08),
                      ),
                      icon: const Icon(Icons.close, color: Color(0xFF111827)),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromoSlideData {
  final _PromoIllustrationType illustration;
  final String title;
  final String message;
  final Color color;
  final bool showActivateButton;
  final List<String> highlights;

  const _PromoSlideData({
    required this.illustration,
    required this.title,
    required this.message,
    required this.color,
    this.showActivateButton = false,
    this.highlights = const [],
  });
}

enum _PromoIllustrationType { gift, folders, tags, premium }

class _PromoSlide extends StatelessWidget {
  final _PromoSlideData slide;

  const _PromoSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 52, 24, 52),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            slide.color.withValues(alpha: 0.18),
            Colors.white,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Center(child: _PromoIllustration(slide: slide)),
          ),
          const SizedBox(height: 14),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 25,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slide.message,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 14,
              height: 1.28,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (slide.highlights.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...slide.highlights.take(3).map(
                  (highlight) => _SlideBenefit(
                    color: slide.color,
                    text: highlight,
                  ),
                ),
          ],
          if (slide.showActivateButton) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: slide.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 13,
                ),
              ),
              icon: const Icon(Icons.workspace_premium),
              label: const Text(
                'Attiva Premium gratis',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PromoIllustration extends StatelessWidget {
  final _PromoSlideData slide;

  const _PromoIllustration({required this.slide});

  @override
  Widget build(BuildContext context) {
    switch (slide.illustration) {
      case _PromoIllustrationType.gift:
        return _GiftIllustration(color: slide.color);
      case _PromoIllustrationType.folders:
        return _FoldersIllustration(color: slide.color);
      case _PromoIllustrationType.tags:
        return _TagsIllustration(color: slide.color);
      case _PromoIllustrationType.premium:
        return _PremiumIllustration(color: slide.color);
    }
  }
}

class _IllustrationFrame extends StatelessWidget {
  final Color color;
  final Widget child;

  const _IllustrationFrame({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GiftIllustration extends StatelessWidget {
  final Color color;

  const _GiftIllustration({required this.color});

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      color: color,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(Icons.card_giftcard, color: color, size: 46),
          ),
          const SizedBox(height: 14),
          _InfoPill(color: color, icon: Icons.auto_awesome, label: '30 giorni'),
          const SizedBox(height: 8),
          _InfoPill(color: color, icon: Icons.euro, label: 'Poi 2,99/mese'),
        ],
      ),
    );
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
          _FolderPill(color: color, label: 'Viaggi', large: true),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallChip(label: 'Giappone'),
              _SmallChip(label: 'Francia'),
              _SmallChip(label: 'India'),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Dentro Giappone:',
                  style: TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SmallChip(label: 'Ristoranti'),
                    _SmallChip(label: 'Monumenti'),
                    _SmallChip(label: 'Esperienze'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsIllustration extends StatelessWidget {
  final Color color;

  const _TagsIllustration({required this.color});

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: color),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Cerca: regalo',
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
              _TagChip(color: color, label: 'regalo'),
              _TagChip(color: color, label: 'ricetta'),
              _TagChip(color: color, label: 'legno'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PremiumIllustration extends StatelessWidget {
  final Color color;

  const _PremiumIllustration({required this.color});

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      color: color,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MetricBox(color: color, icon: Icons.insights, label: 'Stats'),
              const SizedBox(width: 10),
              _MetricBox(color: color, icon: Icons.block, label: 'No ads'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(Icons.workspace_premium, color: color),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Premium attivo',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w900,
                    ),
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

class _FolderPill extends StatelessWidget {
  final Color color;
  final String label;
  final bool large;

  const _FolderPill({
    required this.color,
    required this.label,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 10,
        vertical: large ? 12 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder, color: color, size: large ? 24 : 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;

  const _SmallChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF4B5563),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final Color color;
  final String label;

  const _TagChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#$label',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _InfoPill({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideBenefit extends StatelessWidget {
  final Color color;
  final String text;

  const _SlideBenefit({
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Text('✨', style: TextStyle(color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontWeight: FontWeight.w800,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _MetricBox({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
