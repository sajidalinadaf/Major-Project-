import 'package:flutter/foundation.dart';
import '../models/inventory_item.dart';
import '../services/api_service.dart';

enum LoadState { idle, loading, loaded, error }

/// OmniShelf Inventory Provider
/// Central state container for the entire inventory dataset.
/// Exposes FEFO-sorted lists, KPI metrics, and filter helpers.
class InventoryProvider extends ChangeNotifier {
  List<InventoryItem> _items = [];
  LoadState _state = LoadState.idle;
  String _errorMessage = '';
  String _categoryFilter = 'All';
  String _searchQuery = '';

  // ── Getters ──────────────────────────────────────────────────────────────────

  LoadState get state => _state;
  String get errorMessage => _errorMessage;
  bool get isLoading => _state == LoadState.loading;
  String get categoryFilter => _categoryFilter;
  String get searchQuery => _searchQuery;

  List<String> get categories {
    final cats = _items.map((e) => e.category).toSet().toList()..sort();
    return ['All', ...cats];
  }

  /// All items — already FEFO sorted by the API / mock
  List<InventoryItem> get allItems => _filteredItems(_items);

  /// Items expiring within 7 days or already expired, with stock > 0
  List<InventoryItem> get alertItems => _items
      .where((i) => i.quantity > 0 && (i.isExpired || i.isExpiringSoon))
      .toList();

  /// Items expiring within 3 days (critical)
  List<InventoryItem> get criticalItems => _items
      .where((i) => i.quantity > 0 && i.daysUntilExpiry <= 3)
      .toList();

  // ── KPI Metrics ──────────────────────────────────────────────────────────────

  int get totalSKUs => _items.length;
  int get totalUnits => _items.fold(0, (sum, i) => sum + i.quantity);
  int get expiringCount => alertItems.length;
  int get expiredCount => _items.where((i) => i.isExpired && i.quantity > 0).length;
  double get avgWasteRisk => _items.isEmpty
      ? 0
      : _items.fold<double>(0, (s, i) => s + i.wasteRiskScore) / _items.length;

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> loadInventory({String? sku}) async {
    _state = LoadState.loading;
    _errorMessage = '';
    notifyListeners();
    try {
      _items = await ApiService.fetchInventory(sku: sku);
      _state = LoadState.loaded;
    } on Exception catch (e) {
      _state = LoadState.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> refresh() => loadInventory();

  Future<InventoryItem?> addItem(Map<String, dynamic> payload) async {
    try {
      final item = await ApiService.createOrUpdateItem(payload);
      final idx = _items.indexWhere((i) => i.id == item.id);
      if (idx >= 0) {
        _items[idx] = item;
      } else {
        _items.add(item);
      }
      // Re-sort FEFO
      _items.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      notifyListeners();
      return item;
    } on Exception catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> dispatch({
    required String batchNumber,
    required String sku,
    required int quantity,
  }) async {
    try {
      await ApiService.dispatch(
          batchNumber: batchNumber, sku: sku, quantity: quantity);
      // Optimistic local update
      final id  = '$batchNumber#$sku';
      final idx = _items.indexWhere((i) => i.id == id);
      if (idx >= 0) {
        final updated = _items[idx].copyWith(
            quantity: (_items[idx].quantity - quantity).clamp(0, 999999));
        _items[idx] = updated;
        notifyListeners();
      }
      return true;
    } on Exception catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ── Filters ──────────────────────────────────────────────────────────────────

  void setCategoryFilter(String category) {
    _categoryFilter = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  List<InventoryItem> _filteredItems(List<InventoryItem> src) {
    var result = src;
    if (_categoryFilter != 'All') {
      result = result.where((i) => i.category == _categoryFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((i) =>
          i.productName.toLowerCase().contains(q) ||
          i.sku.toLowerCase().contains(q) ||
          i.batchNumber.toLowerCase().contains(q)).toList();
    }
    return result;
  }
}