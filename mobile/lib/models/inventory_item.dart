/// OmniShelf — InventoryItem model
/// Mirrors the DynamoDB OmniShelfInventory schema and adds FEFO helpers.
library;

enum ExpiryStatus { safe, warning, critical, expired }
enum WasteRiskLevel { low, medium, high, extreme }

class InventoryItem {
  final String id;           // PK: batchNumber#sku
  final String productName;
  final String sku;
  final String batchNumber;
  final DateTime expiryDate;
  final int quantity;
  final String storageGuideline;
  final String? imageUrl;
  final String category;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InventoryItem({
    required this.id,
    required this.productName,
    required this.sku,
    required this.batchNumber,
    required this.expiryDate,
    required this.quantity,
    required this.storageGuideline,
    this.imageUrl,
    this.category = 'General',
    required this.createdAt,
    required this.updatedAt,
  });

  // ── FEFO helpers ────────────────────────────────────────────────────────────

  int get daysUntilExpiry =>
      expiryDate.difference(DateTime.now()).inDays;

  bool get isExpired => daysUntilExpiry < 0;
  bool get isExpiringSoon => daysUntilExpiry >= 0 && daysUntilExpiry <= 7;

  /// Waste risk score: 0 (none) → 100 (maximum).
  /// Combines proximity to expiry with stock quantity.
  double get wasteRiskScore {
    if (isExpired) return 100.0;
    if (quantity == 0) return 0.0;
    final expiryFactor = (daysUntilExpiry <= 0)
        ? 1.0
        : (1.0 - (daysUntilExpiry / 30.0)).clamp(0.0, 1.0);
    final qtyFactor = (quantity / 100.0).clamp(0.0, 1.0);
    return ((expiryFactor * 0.7 + qtyFactor * 0.3) * 100).clamp(0, 100);
  }

  WasteRiskLevel get wasteRiskLevel {
    final s = wasteRiskScore;
    if (s >= 80) return WasteRiskLevel.extreme;
    if (s >= 50) return WasteRiskLevel.high;
    if (s >= 20) return WasteRiskLevel.medium;
    return WasteRiskLevel.low;
  }

  ExpiryStatus get expiryStatus {
    if (isExpired) return ExpiryStatus.expired;
    if (daysUntilExpiry <= 3) return ExpiryStatus.critical;
    if (daysUntilExpiry <= 7) return ExpiryStatus.warning;
    return ExpiryStatus.safe;
  }

  // ── JSON ─────────────────────────────────────────────────────────────────────

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        id:               json['id'] as String,
        productName:      json['productName'] as String,
        sku:              json['sku'] as String,
        batchNumber:      json['batchNumber'] as String,
        expiryDate:       DateTime.parse(json['expiryDate'] as String),
        quantity:         (json['quantity'] as num).toInt(),
        storageGuideline: json['storageGuideline'] as String? ?? '',
        imageUrl:         json['imageUrl'] as String?,
        category:         json['category'] as String? ?? 'General',
        createdAt:        DateTime.parse(json['createdAt'] as String),
        updatedAt:        DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id':               id,
        'productName':      productName,
        'sku':              sku,
        'batchNumber':      batchNumber,
        'expiryDate':       expiryDate.toIso8601String(),
        'quantity':         quantity,
        'storageGuideline': storageGuideline,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'category':         category,
        'createdAt':        createdAt.toIso8601String(),
        'updatedAt':        updatedAt.toIso8601String(),
      };

  InventoryItem copyWith({
    String? id, String? productName, String? sku, String? batchNumber,
    DateTime? expiryDate, int? quantity, String? storageGuideline,
    String? imageUrl, String? category, DateTime? createdAt, DateTime? updatedAt,
  }) => InventoryItem(
        id:               id ?? this.id,
        productName:      productName ?? this.productName,
        sku:              sku ?? this.sku,
        batchNumber:      batchNumber ?? this.batchNumber,
        expiryDate:       expiryDate ?? this.expiryDate,
        quantity:         quantity ?? this.quantity,
        storageGuideline: storageGuideline ?? this.storageGuideline,
        imageUrl:         imageUrl ?? this.imageUrl,
        category:         category ?? this.category,
        createdAt:        createdAt ?? this.createdAt,
        updatedAt:        updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'InventoryItem($productName, batch=$batchNumber, expiry=$expiryDate, qty=$quantity)';
}