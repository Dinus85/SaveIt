import 'package:flutter/material.dart';
import 'package:savein/models.dart';
import '../services/reminder_service.dart';

class ReminderDialog extends StatefulWidget {
  // Campi per reminder su post
  final String? postId;
  final String? postTitle;
  final String? postUrl;
  final String? postFolderId;

  // Campi per reminder su cartella
  final String? targetFolderId;
  final String? folderName;

  final bool isDarkTheme;

  /// Costruttore per reminder su un post
  const ReminderDialog.forPost({
    super.key,
    required String this.postId,
    required String this.postTitle,
    required String this.postUrl,
    this.postFolderId,
    required this.isDarkTheme,
  })  : targetFolderId = null,
        folderName = null;

  /// Costruttore per reminder su una cartella
  const ReminderDialog.forFolder({
    super.key,
    required String folderId,
    required String this.folderName,
    required this.isDarkTheme,
  })  : targetFolderId = folderId,
        postId = null,
        postTitle = null,
        postUrl = null,
        postFolderId = null;

  bool get isFolderMode => targetFolderId != null;

  /// Titolo da mostrare nel dialog
  String get displayTitle => isFolderMode
      ? (folderName?.isNotEmpty == true ? folderName! : 'Cartella')
      : (postTitle?.isNotEmpty == true ? postTitle! : postUrl ?? '');

  @Deprecated('Usa ReminderDialog.forPost o ReminderDialog.forFolder')
  const ReminderDialog({
    super.key,
    required String this.postId,
    required String this.postTitle,
    required String this.postUrl,
    String? folderId,
    required this.isDarkTheme,
  })  : targetFolderId = null,
        folderName = null,
        postFolderId = folderId;

  @override
  State<ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<ReminderDialog> {
  List<Reminder> _reminders = [];
  bool _loading = true;
  bool _saving = false;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isYearly = false;

  TimeOfDay _initialPickerTime() {
    final now = DateTime.now().add(const Duration(minutes: 5));
    return TimeOfDay(hour: now.hour, minute: now.minute);
  }

  DateTime? _selectedDateTime() {
    final date = _selectedDate;
    final time = _selectedTime;
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatItalianDate(DateTime date) {
    const months = [
      'gennaio',
      'febbraio',
      'marzo',
      'aprile',
      'maggio',
      'giugno',
      'luglio',
      'agosto',
      'settembre',
      'ottobre',
      'novembre',
      'dicembre',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  void initState() {
    super.initState();
    _loadReminders();
    // Pre-seleziona oggi come data predefinita
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  Future<void> _loadReminders() async {
    final stream = widget.isFolderMode
        ? ReminderService.instance.getFolderReminders(widget.targetFolderId!)
        : ReminderService.instance.getPostReminders(widget.postId!);
    stream.listen((reminders) {
      if (mounted) {
        setState(() {
          _reminders = reminders;
          _loading = false;
        });
      }
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? _initialPickerTime(),
      builder: (context, child) {
        return Theme(
          data: widget.isDarkTheme
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(primary: Colors.blue),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(primary: Colors.blue),
                ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate: today.subtract(const Duration(days: 365)), // Permetti di vedere oggi chiaramente
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Scegli il giorno del reminder',
      cancelText: 'Annulla',
      confirmText: 'Conferma',
      fieldLabelText: 'Data reminder',
      fieldHintText: 'gg/mm/aaaa',
      builder: (context, child) {
        return Theme(
          data: widget.isDarkTheme
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(primary: Colors.blue),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(primary: Colors.blue),
                ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveReminder() async {
    final selectedDateTime = _selectedDateTime();
    if (selectedDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona data e ora del reminder.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!selectedDateTime.isAfter(DateTime.now().subtract(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Per oggi scegli un orario successivo a quello attuale.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.isFolderMode) {
        await ReminderService.instance.createFolderReminder(
          folderId: widget.targetFolderId!,
          folderName: widget.folderName ?? '',
          day: _selectedDate!.day,
          month: _selectedDate!.month,
          hour: _selectedTime!.hour,
          minute: _selectedTime!.minute,
          isYearly: _isYearly,
        );
      } else {
        await ReminderService.instance.createReminder(
          postId: widget.postId!,
          postTitle: widget.postTitle ?? '',
          postUrl: widget.postUrl ?? '',
          folderId: widget.postFolderId,
          day: _selectedDate!.day,
          month: _selectedDate!.month,
          hour: _selectedTime!.hour,
          minute: _selectedTime!.minute,
          isYearly: _isYearly,
        );
      }
      if (mounted) {
        setState(() {
          _selectedDate = null;
          _selectedTime = null;
          _isYearly = false;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder salvato!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    try {
      await ReminderService.instance.deleteReminder(reminder);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder eliminato'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDarkTheme ? Colors.grey[900]! : Colors.white;
    final textColor = widget.isDarkTheme ? Colors.white : Colors.black87;
    final subtitleColor = widget.isDarkTheme ? Colors.white60 : Colors.black54;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titolo
            Row(
              children: [
                Icon(
                  widget.isFolderMode
                      ? Icons.folder_outlined
                      : Icons.notifications_active,
                  color: widget.isFolderMode ? Colors.orange : Colors.blue,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isFolderMode ? 'Reminder cartella' : 'Reminder',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: subtitleColor, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              widget.displayTitle,
              style: TextStyle(color: subtitleColor, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 20),

            // Reminder esistenti
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_reminders.isNotEmpty) ...[
              Text(
                'Reminder attivi',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ..._reminders
                  .map((r) => _buildReminderChip(r, textColor, subtitleColor)),
              const SizedBox(height: 16),
              Divider(color: subtitleColor.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
            ],

            // Aggiungi nuovo reminder
            Text(
              'Aggiungi reminder',
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // Selettore data
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color:
                      widget.isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedDate != null
                        ? Colors.blue
                        : subtitleColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color:
                          _selectedDate != null ? Colors.blue : subtitleColor,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _selectedDate != null
                          ? _formatItalianDate(_selectedDate!)
                          : 'Scegli una data...',
                      style: TextStyle(
                        color:
                            _selectedDate != null ? textColor : subtitleColor,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Selettore orario
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color:
                      widget.isDarkTheme ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedTime != null
                        ? Colors.blue
                        : subtitleColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      color:
                          _selectedTime != null ? Colors.blue : subtitleColor,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _selectedTime != null
                          ? _selectedTime!.format(context)
                          : 'Scegli un orario...',
                      style: TextStyle(
                        color:
                            _selectedTime != null ? textColor : subtitleColor,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _selectedTime != null ? 'Cambia orario' : 'Seleziona',
                      style: TextStyle(color: subtitleColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Toggle ricorrenza annuale
            GestureDetector(
              onTap: () => setState(() => _isYearly = !_isYearly),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _isYearly ? Colors.blue : Colors.transparent,
                      border: Border.all(
                        color: _isYearly ? Colors.blue : subtitleColor,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: _isYearly
                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ripeti ogni anno',
                    style: TextStyle(color: textColor, fontSize: 14),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.loop, color: subtitleColor, size: 16),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Bottone salva
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_selectedDate == null ||
                        _selectedTime == null ||
                        _saving)
                    ? null
                    : _saveReminder,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.notifications_active, size: 18),
                label: Text(_saving ? 'Salvando...' : 'Salva reminder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.blue.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderChip(
      Reminder reminder, Color textColor, Color subtitleColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.alarm, color: Colors.blue, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reminder.displayDate,
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: () => _deleteReminder(reminder),
            child: Icon(Icons.delete_outline, color: Colors.red[400], size: 18),
          ),
        ],
      ),
    );
  }
}
