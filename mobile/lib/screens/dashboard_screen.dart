import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/omnishelf_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().loadInventory();
      _animCtrl.forward();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: AppTheme.surfaceCard,
        onRefresh: () => context.read<InventoryProvider>().refresh(),
        child: CustomScrollView(
          slivers: [
            _buildAppBar(context),
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _buildBody(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: AppTheme.background,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('EEEE, d MMM').format(DateTime.now()),
                style: const TextStyle(
                    color: AppTheme.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w400)),
            const Text('OmniShelf',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
          ],
        ),
        // 0x15 = ~8% alpha for teal tint background
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x1500D4AA), Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      actions: [
        Consumer<InventoryProvider>(
          builder: (_, p, __) => Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: AppTheme.textPrimary),
                onPressed: () {},
              ),
              if (p.alertItems.isNotEmpty)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.statusExpired,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.statusExpired.withValues(alpha: 0.6),
                          blurRadius: 4,
                        )
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Consumer<InventoryProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.allItems.isEmpty) {
            return const SizedBox(
              height: 400,
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildKpiGrid(provider),
              const SizedBox(height: 24),
              _buildSectionHeader('FEFO Priority Queue',
                  '${provider.allItems.length} items'),
              const SizedBox(height: 8),
              _buildCategoryChips(provider),
              const SizedBox(height: 8),
              _buildSearchBar(provider),
              const SizedBox(height: 12),
              if (provider.alertItems.isNotEmpty) ...[
                _buildAlertBanner(provider),
                const SizedBox(height: 12),
              ],
              ...provider.allItems.map((item) => FefoItemCard(
                    item: item,
                    onDispatch: () => _showDispatchSheet(context, item),
                  )),
              if (provider.allItems.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('No items match your filter.',
                        style: TextStyle(color: AppTheme.textHint)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiGrid(InventoryProvider p) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        KpiCard(
          label: 'Total SKUs',
          value: p.totalSKUs.toString(),
          icon: Icons.inventory_2_outlined,
          color: AppTheme.primary,
          subtitle: 'active batches',
        ),
        KpiCard(
          label: 'Total Units',
          value: p.totalUnits.toString(),
          icon: Icons.layers_outlined,
          color: AppTheme.accent,
          subtitle: 'across all batches',
        ),
        KpiCard(
          label: 'Expiring Soon',
          value: p.expiringCount.toString(),
          icon: Icons.schedule_outlined,
          color: AppTheme.statusWarning,
          subtitle: 'within 7 days',
        ),
        KpiCard(
          label: 'Avg Waste Risk',
          value: '${p.avgWasteRisk.toStringAsFixed(0)}%',
          icon: Icons.warning_amber_rounded,
          color: p.avgWasteRisk > 50
              ? AppTheme.statusCritical
              : AppTheme.statusSafe,
          subtitle: 'portfolio score',
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String sub) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          Text(sub,
              style: const TextStyle(
                  color: AppTheme.textHint, fontSize: 12)),
        ],
      );

  Widget _buildCategoryChips(InventoryProvider p) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: p.categories.map((cat) {
          final selected = cat == p.categoryFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(cat),
              selected: selected,
              onSelected: (_) => p.setCategoryFilter(cat),
              selectedColor: AppTheme.primary.withValues(alpha: 0.2),
              checkmarkColor: AppTheme.primary,
              labelStyle: TextStyle(
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w400),
              side: BorderSide(
                  color: selected ? AppTheme.primary : AppTheme.divider),
              backgroundColor: AppTheme.surfaceCard,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar(InventoryProvider p) {
    return TextField(
      onChanged: p.setSearchQuery,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: const InputDecoration(
        hintText: 'Search products, SKU, batch...',
        prefixIcon: Icon(Icons.search, color: AppTheme.textHint, size: 20),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }

  Widget _buildAlertBanner(InventoryProvider p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.statusCritical.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.statusCritical.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppTheme.statusCritical, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${p.alertItems.length} item(s) expiring within 7 days or already expired.',
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showDispatchSheet(BuildContext context, dynamic item) {
    final ctrl = TextEditingController(text: '1');
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceSheet,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dispatch Stock',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(item.productName as String,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Units to dispatch (max ${item.quantity})',
                suffixText: 'units',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final qty = int.tryParse(ctrl.text) ?? 0;
                  Navigator.pop(context);
                  final ok =
                      await context.read<InventoryProvider>().dispatch(
                          batchNumber: item.batchNumber as String,
                          sku: item.sku as String,
                          quantity: qty);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? 'Dispatched $qty units of ${item.productName}'
                          : context
                              .read<InventoryProvider>()
                              .errorMessage),
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