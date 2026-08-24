import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/inventory_item.dart';

/// OmniShelf API Service
/// Connects to the AWS API Gateway backend with offline mock fallback.
class ApiService {
  static const String _baseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  // Set to true to force mock data (useful during development)
  static bool useMockFallback = _baseUrl.isEmpty;

  static const Duration _timeout = Duration(seconds: 15);

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // ── GET /inventory ──────────────────────────────────────────────────────────

  static Future<List<InventoryItem>> fetchInventory({String? sku}) async {
    if (useMockFallback) return _mockInventory();
    try {
      final uri = Uri.parse('$_baseUrl/inventory')
          .replace(queryParameters: sku != null ? {'sku': sku} : null);
      final resp = await http.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>;
        return items.map((e) => InventoryItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      throw ApiException('GET /inventory failed: ${resp.statusCode}');
    } on SocketException {
      debugPrint('[ApiService] No internet — using mock data');
      return _mockInventory();
    } on Exception catch (e) {
      debugPrint('[ApiService] Error: $e — using mock data');
      return _mockInventory();
    }
  }

  // ── POST /inventory ─────────────────────────────────────────────────────────

  static Future<InventoryItem> createOrUpdateItem(Map<String, dynamic> payload) async {
    if (useMockFallback) {
      await Future.delayed(const Duration(milliseconds: 600));
      final now = DateTime.now().toUtc().toIso8601String();
      final id  = '${payload['batchNumber']}#${payload['sku']}';
      return InventoryItem.fromJson({...payload, 'id': id, 'createdAt': now, 'updatedAt': now});
    }
    final resp = await http
        .post(Uri.parse('$_baseUrl/inventory'),
            headers: _headers, body: json.encode(payload))
        .timeout(_timeout);
    if (resp.statusCode == 201) {
      return InventoryItem.fromJson(json.decode(resp.body) as Map<String, dynamic>);
    }
    throw ApiException('POST /inventory failed: ${resp.statusCode} — ${resp.body}');
  }

  // ── POST /dispatch ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> dispatch({
    required String batchNumber,
    required String sku,
    required int quantity,
  }) async {
    if (useMockFallback) {
      await Future.delayed(const Duration(milliseconds: 500));
      return {'message': 'Dispatched $quantity units (mock)', 'remainingStock': 0};
    }
    final resp = await http
        .post(Uri.parse('$_baseUrl/dispatch'),
            headers: _headers,
            body: json.encode({'batchNumber': batchNumber, 'sku': sku, 'quantity': quantity}))
        .timeout(_timeout);
    if (resp.statusCode == 200) return json.decode(resp.body) as Map<String, dynamic>;
    final body = json.decode(resp.body) as Map<String, dynamic>;
    throw ApiException(body['error'] as String? ?? 'Dispatch failed: ${resp.statusCode}');
  }

  // ── POST /ocr ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> extractFromImage(String base64Image) async {
    if (useMockFallback) {
      await Future.delayed(const Duration(seconds: 2));
      return _mockOcrResult();
    }
    final resp = await http
        .post(Uri.parse('$_baseUrl/ocr'),
            headers: _headers,
            body: json.encode({'image': base64Image, 'contentType': 'image/jpeg'}))
        .timeout(const Duration(seconds: 45));
    if (resp.statusCode == 200) return json.decode(resp.body) as Map<String, dynamic>;
    throw ApiException('POST /ocr failed: ${resp.statusCode}');
  }

  // ── Mock data ────────────────────────────────────────────────────────────────

  static List<InventoryItem> _mockInventory() {
    final now = DateTime.now();
    final items = [
      _mock('Amul Fresh Butter 500g',        'AMF-500', 'BATCH-DAIRY-001', now.add(const Duration(days: 92)),  48, 'Dairy',          'Store below 4°C'),
      _mock('Mother Dairy Whole Milk 1L',    'MWM-1L',  'BATCH-DAIRY-002', now.add(const Duration(days: 2)),   30, 'Dairy',          'Store at 2–4°C. Consume within 2 days of opening.'),
      _mock('Fresh Paneer 200g',             'NPC-200', 'BATCH-DAIRY-003', now.add(const Duration(days: 3)),   18, 'Dairy',          'Refrigerate below 6°C. Do not freeze.'),
      _mock('Amul Masti Dahi 200g',          'AYC-200', 'BATCH-DAIRY-004', now.add(const Duration(days: 4)),   60, 'Dairy',          'Keep refrigerated below 8°C.'),
      _mock('Britannia Wheat Bread 400g',    'BWB-400', 'BATCH-BAKERY-001',now.add(const Duration(days: 2)),   40, 'Bakery',         'Store in a cool dry place.'),
      _mock('Goodday Butter Puffs 6-Pack',   'GBP-6PK', 'BATCH-BAKERY-002',now.subtract(const Duration(days: 1)), 15, 'Bakery',     'Keep in airtight container.'),
      _mock('English Oven Multigrain Buns',  'ENW-200', 'BATCH-BAKERY-003',now.add(const Duration(days: 5)),   22, 'Bakery',         'Store at room temperature.'),
      _mock('Fresh Spinach 500g',            'FSP-500', 'BATCH-PROD-001',  now.add(const Duration(days: 3)),   20, 'Produce',        'Refrigerate at 2–4°C.'),
      _mock('Roma Tomatoes 1kg',             'RTP-1KG', 'BATCH-PROD-002',  now.add(const Duration(days: 7)),   35, 'Produce',        'Store at room temperature.'),
      _mock('Green Peas Shelled 500g',       'GRP-500', 'BATCH-PROD-003',  now.subtract(const Duration(days: 3)), 12, 'Produce',    'Refrigerate immediately.'),
      _mock('Fresh Carrots Baby 1kg',        'FCR-1KG', 'BATCH-PROD-004',  now.add(const Duration(days: 4)),   28, 'Produce',        'Refrigerate at 2–5°C.'),
      _mock('Nagpur Oranges 1kg',            'ONG-1KG', 'BATCH-PROD-005',  now.subtract(const Duration(days: 2)), 8, 'Produce',     'Store at room temperature.'),
      _mock('Maggi 2-Minute Noodles 70g',    'MAG-70',  'BATCH-PKG-001',   now.add(const Duration(days: 80)),  200,'Packaged Goods', 'Store in a cool dry place.'),
      _mock('Saffola Gold Sunflower Oil 1L', 'SFL-1L',  'BATCH-PKG-002',   now.add(const Duration(days: 25)),  55, 'Packaged Goods', 'Keep away from direct sunlight.'),
      _mock('Haldiram Bhujia 250g',          'HPF-250', 'BATCH-PKG-003',   now.add(const Duration(days: 30)),  90, 'Packaged Goods', 'Keep bag sealed after opening.'),
      _mock('Bournvita Health Drink 400g',   'BOV-400', 'BATCH-PKG-004',   now.subtract(const Duration(days: 2)), 10, 'Packaged Goods','Store in a cool dry place.'),
    ];
    // FEFO sort: earliest expiry first
    items.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return items;
  }

  static InventoryItem _mock(
      String name, String sku, String batch, DateTime expiry,
      int qty, String category, String storage) {
    final id  = '$batch#$sku';
    final now = DateTime.now().toUtc();
    return InventoryItem(
      id: id, productName: name, sku: sku, batchNumber: batch,
      expiryDate: expiry, quantity: qty, storageGuideline: storage,
      category: category, createdAt: now, updatedAt: now,
    );
  }

  static Map<String, dynamic> _mockOcrResult() => {
        'productName':      'Amul Gold Full Cream Milk 1L',
        'sku':              'AGL-1L',
        'batchNumber':      'BATCH-${DateTime.now().millisecondsSinceEpoch}',
        'expiryDate':       DateTime.now().add(const Duration(days: 5)).toIso8601String().substring(0, 10),
        'storageGuideline': 'Store at 2–4°C. Consume within 2 days of opening.',
      };
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => 'ApiException: $message';
}