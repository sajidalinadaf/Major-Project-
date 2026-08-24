import 'package:flutter/material.dart';
import '../models/inventory_item.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// KPI Card
// ═══════════════════════════════════════════════════════════════════════════════

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                if (onTap != null)
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: AppTheme.textHint, size: 12),
              ],
            ),
            const SizedBox(height: 12),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: const TextStyle(
                      color: AppTheme.textHint, fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FEFO Item Card
// ═══════════════════════════════════════════════════════════════════════════════

class FefoItemCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback? onDispatch;
  final VoidCallback? onTap;

  const FefoItemCard({
    super.key,
    required this.item,
    this.onDispatch,
    this.onTap,
  });

  Color get _statusColor {
    switch (item.expiryStatus) {
      case ExpiryStatus.expired:  return AppTheme.statusExpired;
      case ExpiryStatus.critical: return AppTheme.statusCritical;
      case ExpiryStatus.warning:  return AppTheme.statusWarning;
      case ExpiryStatus.safe:     return AppTheme.statusSafe;
    }
  }

  String get _expiryLabel {
    final d = item.daysUntilExpiry;
    if (d < 0)  return 'Expired ${d.abs()}d ago';
    if (d == 0) return 'Expires today';
    if (d == 1) return 'Expires tomorrow';
    return 'Expires in ${d}d';
  }

  String get _riskLabel {
    switch (item.wasteRiskLevel) {
      case WasteRiskLevel.extreme: return 'Extreme Risk';
      case WasteRiskLevel.high:    return 'High Risk';
      case WasteRiskLevel.medium:  return 'Medium Risk';
      case WasteRiskLevel.low:     return 'Low Risk';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName,
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('${item.sku}  •  Batch: ${item.batchNumber}',
                                style: const TextStyle(
                                    color: AppTheme.textHint, fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_expiryLabel,
                            style: TextStyle(
                                color: _statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Metric(
                          icon: Icons.inventory_2_outlined,
                          label: 'Stock',
                          value: '${item.quantity} units'),
                      const SizedBox(width: 16),
                      _Metric(
                          icon: Icons.category_outlined,
                          label: 'Category',
                          value: item.category),
                      const SizedBox(width: 16),
                      _Metric(
                          icon: Icons.warning_amber_rounded,
                          label: 'Risk',
                          value: _riskLabel,
                          valueColor: _statusColor),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: item.wasteRiskScore / 100,
                            backgroundColor: AppTheme.background,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(_statusColor),
                            minHeight: 5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${item.wasteRiskScore.toStringAsFixed(0)}%',
                          style: TextStyle(
                              color: _statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  if (onDispatch != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onDispatch,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _statusColor,
                          side: BorderSide(
                              color: _statusColor.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.local_shipping_outlined, size: 14),
                        label: const Text('Dispatch Stock',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _Metric({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 12, color: AppTheme.textHint),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppTheme.textHint, fontSize: 10)),
                  Text(value,
                      style: TextStyle(
                          color: valueColor ?? AppTheme.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
}