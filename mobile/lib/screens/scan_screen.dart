import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

enum ScanStep { idle, picked, extracting, review, saving, done }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  File? _imageFile;
  ScanStep _step = ScanStep.idle;
  String _errorMsg = '';

  final _nameCtrl    = TextEditingController();
  final _skuCtrl     = TextEditingController();
  final _batchCtrl   = TextEditingController();
  final _expiryCtrl  = TextEditingController();
  final _storageCtrl = TextEditingController();
  final _qtyCtrl     = TextEditingController(text: '1');

  @override
  void dispose() {
    for (final c in [_nameCtrl, _skuCtrl, _batchCtrl, _expiryCtrl,
                     _storageCtrl, _qtyCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAndExtract(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
          source: source, imageQuality: 85, maxWidth: 1280);
      if (picked == null) return;
      setState(() {
        _imageFile = File(picked.path);
        _step      = ScanStep.extracting;
        _errorMsg  = '';
      });

      final bytes  = await _imageFile!.readAsBytes();
      final b64    = base64Encode(bytes);
      final result = await ApiService.extractFromImage(b64);

      _nameCtrl.text    = result['productName']      ?? '';
      _skuCtrl.text     = result['sku']              ?? '';
      _batchCtrl.text   = result['batchNumber']      ?? '';
      _expiryCtrl.text  = result['expiryDate']       ?? '';
      _storageCtrl.text = result['storageGuideline'] ?? '';

      setState(() => _step = ScanStep.review);
    } on Exception catch (e) {
      setState(() {
        _step     = ScanStep.idle;
        _errorMsg = e.toString();
      });
    }
  }

  Future<void> _saveItem() async {
    setState(() => _step = ScanStep.saving);
    final payload = {
      'productName':      _nameCtrl.text.trim(),
      'sku':              _skuCtrl.text.trim(),
      'batchNumber':      _batchCtrl.text.trim(),
      'expiryDate':       _expiryCtrl.text.trim(),
      'quantity':         int.tryParse(_qtyCtrl.text) ?? 1,
      'storageGuideline': _storageCtrl.text.trim(),
    };
    final item = await context.read<InventoryProvider>().addItem(payload);
    if (!mounted) return;
    if (item != null) {
      setState(() => _step = ScanStep.done);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Item saved to inventory \u2713'),
        backgroundColor: AppTheme.statusSafe,
      ));
      Future.delayed(const Duration(seconds: 2), _resetState);
    } else {
      setState(() {
        _step     = ScanStep.review;
        _errorMsg = context.read<InventoryProvider>().errorMessage;
      });
    }
  }

  void _resetState() {
    if (!mounted) return;
    setState(() {
      _imageFile = null;
      _step      = ScanStep.idle;
      _errorMsg  = '';
      for (final c in [_nameCtrl, _skuCtrl, _batchCtrl, _expiryCtrl, _storageCtrl]) {
        c.clear();
      }
      _qtyCtrl.text = '1';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Scan Product'),
        backgroundColor: AppTheme.background,
        actions: [
          if (_step != ScanStep.idle)
            TextButton(onPressed: _resetState, child: const Text('Reset')),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _buildStepContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case ScanStep.idle:
      case ScanStep.picked:    return _buildIdle();
      case ScanStep.extracting:return _buildExtracting();
      case ScanStep.review:    return _buildReview();
      case ScanStep.saving:    return _buildSaving();
      case ScanStep.done:      return _buildDone();
    }
  }

  Widget _buildIdle() => Column(
        key: const ValueKey('idle'),
        children: [
          // 0x20 teal, 0x10 violet — 8-digit ARGB
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0x2000D4AA), Color(0x107C4DFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: const Column(
              children: [
                Icon(Icons.qr_code_scanner_rounded,
                    color: AppTheme.primary, size: 56),
                SizedBox(height: 12),
                Text('Scan Product Packaging',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text(
                  'Take a photo of the product label.\n'
                  'AI will extract batch number, SKU, and expiry date automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_errorMsg.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.statusExpired.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.statusExpired.withValues(alpha: 0.4)),
              ),
              child: Text(_errorMsg,
                  style: const TextStyle(
                      color: AppTheme.statusExpired, fontSize: 12)),
            ),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _pickAndExtract(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Open Camera'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _pickAndExtract(ImageSource.gallery),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.divider),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose from Gallery'),
            ),
          ),
        ],
      );

  Widget _buildExtracting() => SizedBox(
        key: const ValueKey('extracting'),
        height: 400,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_imageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_imageFile!,
                    height: 160, fit: BoxFit.cover),
              ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text('AI Extracting Label Data...',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Running Textract + Bedrock Claude',
                style: TextStyle(
                    color: AppTheme.textHint, fontSize: 12)),
          ],
        ),
      );

  Widget _buildReview() {
    return Column(
      key: const ValueKey('review'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_imageFile != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(_imageFile!,
                height: 160, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
        ],
        const Row(
          children: [
            Icon(Icons.auto_awesome, color: AppTheme.primary, size: 16),
            SizedBox(width: 6),
            Text('AI Extracted — Review & Confirm',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ),
        const SizedBox(height: 16),
        _field('Product Name', _nameCtrl),
        _field('SKU / Product Code', _skuCtrl),
        _field('Batch Number', _batchCtrl),
        _field('Expiry Date (YYYY-MM-DD)', _expiryCtrl,
            hint: 'e.g. 2025-12-31'),
        _field('Storage Guideline', _storageCtrl, maxLines: 2),
        _field('Initial Stock Quantity', _qtyCtrl,
            keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        if (_errorMsg.isNotEmpty) ...[
          Text(_errorMsg,
              style: const TextStyle(
                  color: AppTheme.statusExpired, fontSize: 12)),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saveItem,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save to Inventory'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _resetState,
            child: const Text('Scan Again',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
        ),
      ],
    );
  }

  Widget _buildSaving() => const SizedBox(
        key: ValueKey('saving'),
        height: 300,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text('Saving to inventory...',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );

  Widget _buildDone() => const SizedBox(
        key: ValueKey('done'),
        height: 300,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  color: AppTheme.statusSafe, size: 64),
              SizedBox(height: 16),
              Text('Item Saved!',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('Returning to scanner...',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _field(String label, TextEditingController ctrl,
      {int maxLines = 1, String? hint, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}