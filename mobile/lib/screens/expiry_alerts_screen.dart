import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/inventory_item.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/omnishelf_widgets.dart';

class ExpiryAlertsScreen extends StatelessWidget {
  const ExpiryAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Expiry Alerts'),
        backgroundColor: AppTheme.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => context.read<InventoryProvider>().refresh(),
          ),
        ],
      ),
      body: Consumer<InventoryProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.allItems.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            );
          }
          final alerts = provider.alertItems;
          if (alerts.isEmpty) return _buildAllClear();

          final expired  = alerts.where((i) => i.isExpired).toList();
          final critical = alerts
              .where((i) => !i.isExpired && i.daysUntilExpiry <= 3)
              .toList();
          final warning = alerts
              .where((i) => !i.isExpired && i.daysUntilExpiry > 3)
              .toList();

          return RefreshIndicator(
            color: AppTheme.primary,
            backgroundColor: AppTheme.surfaceCard,
            onRefresh: () => provider.refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                _buildSummaryBanner(expired.length, critical.length,
                    warning.length),
                const SizedBox(height: 20),

                if (expired.isNotEmpty) ...[
                  _sectionHeader('Expired', expired.length,
                      AppTheme.statusExpired),
                  const SizedBox(height: 8),
                  ...expired.map((item) => FefoItemCard(
                        item: item,
                        onDispatch: () =>
                            _showDispatchSheet(context, item, provider),
                      )),
                  const SizedBox(height: 16),
                ],

                if (critical.isNotEmpty) ...[
                  _sectionHeader('Critical (\u2264 3 days)', critical.length,
                      AppTheme.statusCritical),
                  const SizedBox(height: 8),
                  ...critical.map((item) => FefoItemCard(
                        item: item,
                        onDispatch: () =>
                            _showDispatchSheet(context, item, provider),
                      )),
                  const SizedBox(height: 16),
                ],

                if (warning.isNotEmpty) ...[
                  _sectionHeader('Expiring Soon (4\u20137 days)',
                      warning.length, AppTheme.statusWarning),
                  const SizedBox(height: 8),
                  ...warning.map((item) => FefoItemCard(
                        item: item,
                        onDispatch: () =>
                            _showDispatchSheet(context, item, provider),
                      )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllClear() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppTheme.statusSafe.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_outlined,
                  color: AppTheme.statusSafe, size: 56),
            ),
            const SizedBox(height: 20),
            const Text('All Clear!',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'No items expiring within the next 7 days.\nGreat inventory management!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textSecondary, height: 1.5),
            ),
          ],
        ),
      );

  Widget _buildSummaryBanner(int expired, int critical, int warning) {
    final total = expired + critical + warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 0x20EF4444 = ~12% alpha red, 0x20FF6B35 = ~12% alpha orange
        gradient: const LinearGradient(
          colors: [Color(0x20EF4444), Color(0x20FF6B35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppTheme.statusExpired.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_outlined,
                  color: AppTheme.statusExpired, size: 20),
              const SizedBox(width: 8),
              Text('$total Item(s) Need Attention',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryChip('Expired', expired, AppTheme.statusExpired),
              _summaryChip('Critical', critical, AppTheme.statusCritical),
              _summaryChip('Warning', warning, AppTheme.statusWarning),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Generated: ${DateFormat('d MMM, HH:mm').format(DateTime.now())}',
            style: const TextStyle(
                color: AppTheme.textHint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int count, Color color) => Column(
        children: [
          Text(count.toString(),
              style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11)),
        ],
      );

  Widget _sectionHeader(String title, int count, Color color) => Row(
        children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      );

  void _showDispatchSheet(
      BuildContext context, InventoryItem item, InventoryProvider provider) {
    final ctrl = TextEditingController(text: item.quantity.toString());
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceSheet,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dispatch Stock',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(item.productName,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Quantity (available: ${item.quantity})',
                suffixText: 'units',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final qty = int.tryParse(ctrl.text) ?? 0;
                  Navigator.pop(ctx);
                  final ok = await provider.dispatch(
                      batchNumber: item.batchNumber,
                      sku: item.sku,
                      quantity: qty);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? 'Dispatched $qty units'
                          : provider.errorMessage),
                      backgroundColor: ok
                          ? AppTheme.statusSafe
                          : AppTheme.statusExpired,
                    ));
                  }
                },
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Confirm Dispatch'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}