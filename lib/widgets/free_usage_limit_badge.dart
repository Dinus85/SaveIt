import 'package:flutter/material.dart';
import '../services/plan_limits_service.dart';

class FreeUsageRemainingBadge extends StatefulWidget {
  final String feature;
  final Color? color;

  const FreeUsageRemainingBadge({
    super.key,
    required this.feature,
    this.color,
  });

  @override
  State<FreeUsageRemainingBadge> createState() =>
      _FreeUsageRemainingBadgeState();
}

class _FreeUsageRemainingBadgeState extends State<FreeUsageRemainingBadge> {
  PlanFeatureUsage? _usage;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final usage = await PlanLimitsService.getUsage(forceRefresh: true);
    if (mounted) {
      setState(() {
        _usage = usage[widget.feature];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_usage == null || _usage!.isUnlimited || _usage!.tier == 'premium') {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: widget.color ?? Colors.orange.shade700,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '${_usage!.remaining}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
