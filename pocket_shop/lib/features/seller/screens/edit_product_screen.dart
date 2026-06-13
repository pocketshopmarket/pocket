import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/product.dart';
import '../../../providers/category_provider.dart';
import '../../../services/product_service.dart';

const int _kMaxImages = 5;

class _PendingImage {
  _PendingImage({required this.bytes, this.filePath, required this.filename});
  final Uint8List bytes;
  final String? filePath;
  final String filename;
}

class _VariantRow {
  _VariantRow({String name = '', String value = '', String sku = '', int stock = 0}) {
    nameCtrl = TextEditingController(text: name);
    valueCtrl = TextEditingController(text: value);
    skuCtrl = TextEditingController(text: sku);
    stockCtrl = TextEditingController(text: stock.toString());
  }
  late final TextEditingController nameCtrl;
  late final TextEditingController valueCtrl;
  late final TextEditingController skuCtrl;
  late final TextEditingController stockCtrl;

  void dispose() {
    nameCtrl.dispose();
    valueCtrl.dispose();
    skuCtrl.dispose();
    stockCtrl.dispose();
  }
}

class EditProductScreen extends ConsumerStatefulWidget {
  final int productId;
  const EditProductScreen({super.key, required this.productId});

  @override
  ConsumerState<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends ConsumerState<EditProductScreen> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<String> _existingImageUrls = [];
  final List<_PendingImage> _newImages = [];
  final List<_VariantRow> _variants = [];
  String _quality = 'new';
  int? _categoryId;

  static const _qualityChoices = [
    ('new', 'New'), ('like_new', 'Like new'), ('good', 'Good'),
    ('fair', 'Fair'), ('used', 'Used'),
  ];

  bool get _useDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _descCtrl.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final svc = ProductService();
      final product = await svc.getProduct(widget.productId);
      if (!mounted) return;
      _nameCtrl.text = product.name;
      _priceCtrl.text = product.price.toStringAsFixed(2);
      _stockCtrl.text = product.stockQuantity.toString();
      _descCtrl.text = product.description;
      _quality = product.quality;
      _existingImageUrls = List.from(product.imageUrls);
      for (final v in product.variants) {
        _variants.add(_VariantRow(
          name: v.name,
          value: v.value,
          sku: v.sku,
          stock: v.stockQuantity,
        ));
      }
      // Match category by name against loaded categories.
      final cats = ref.read(allCategoriesProvider).valueOrNull;
      if (cats != null) {
        final match = cats.where((c) => c.name == product.category).firstOrNull;
        _categoryId = match?.id;
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImages() async {
    final room = _kMaxImages - _existingImageUrls.length - _newImages.length;
    if (room <= 0) return;
    if (_useDesktop) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image, allowMultiple: true, withData: true,
      );
      if (!mounted || result == null) return;
      for (final f in result.files) {
        if (_existingImageUrls.length + _newImages.length >= _kMaxImages) break;
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        setState(() => _newImages.add(
          _PendingImage(bytes: bytes, filename: f.name.isNotEmpty ? f.name : 'img.jpg'),
        ));
      }
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () { Navigator.pop(ctx); _pickOne(ImageSource.gallery); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () { Navigator.pop(ctx); _pickOne(ImageSource.camera); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickOne(ImageSource src) async {
    final x = await _picker.pickImage(source: src, maxWidth: 2048, maxHeight: 2048, imageQuality: 88);
    if (!mounted || x == null) return;
    final bytes = await x.readAsBytes();
    final path = kIsWeb ? null : x.path;
    setState(() => _newImages.add(_PendingImage(
      bytes: bytes,
      filePath: (path != null && path.isNotEmpty) ? path : null,
      filename: x.name.isNotEmpty ? x.name : 'img.jpg',
    )));
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _priceCtrl.text.trim().isEmpty || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, price and category are required.'), backgroundColor: AppTheme.error),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final svc = ProductService();
      final data = {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': _priceCtrl.text.trim(),
        'stock_quantity': _stockCtrl.text.trim(),
        'category': _categoryId.toString(),
        'quality': _quality,
      };
      final variants = _variants
          .map((v) => {
                'name': v.nameCtrl.text.trim(),
                'value': v.valueCtrl.text.trim(),
                'sku': v.skuCtrl.text.trim(),
                'stock_quantity': int.tryParse(v.stockCtrl.text.trim()) ?? 0,
              })
          .where((v) => v['name'].toString().isNotEmpty && v['value'].toString().isNotEmpty && v['sku'].toString().isNotEmpty)
          .toList();

      final uploads = _newImages.isNotEmpty
          ? _newImages.map((i) => ProductImageUpload(path: i.filePath, bytes: i.bytes, filename: i.filename)).toList()
          : null;

      await svc.updateProduct(
        productId: widget.productId,
        data: data,
        replacementImages: uploads,
        variants: variants,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product updated'), backgroundColor: AppTheme.success),
      );
      context.go('/seller/products');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit product')),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan)),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit product')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final totalImages = _existingImageUrls.length + _newImages.length;
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Edit product'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan))
                : const Text('Save', style: TextStyle(color: AppTheme.primaryCyan, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Images
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Photos (up to $_kMaxImages)', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _existingImageUrls.length; i++)
                      Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(_existingImageUrls[i], width: 100, height: 100, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _imgPlaceholder()),
                        ),
                        Positioned(right: 2, top: 2, child: IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: Colors.black54, padding: EdgeInsets.zero, minimumSize: const Size(28, 28)),
                          onPressed: () => setState(() => _existingImageUrls.removeAt(i)),
                          icon: const Icon(Icons.close, color: Colors.white, size: 16),
                        )),
                      ]),
                    for (var i = 0; i < _newImages.length; i++)
                      Stack(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_newImages[i].bytes, width: 100, height: 100, fit: BoxFit.cover),
                        ),
                        Positioned(right: 2, top: 2, child: IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: Colors.black54, padding: EdgeInsets.zero, minimumSize: const Size(28, 28)),
                          onPressed: () => setState(() => _newImages.removeAt(i)),
                          icon: const Icon(Icons.close, color: Colors.white, size: 16),
                        )),
                      ]),
                    if (totalImages < _kMaxImages)
                      Material(
                        color: AppTheme.lightCyan.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _pickImages,
                          child: const SizedBox(
                            width: 100,
                            height: 100,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 28),
                                SizedBox(height: 4),
                                Text('Add', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Core fields
          _card(
            child: Column(
              children: [
                TextField(controller: _nameCtrl, textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Product name')),
                const SizedBox(height: 12),
                TextField(controller: _descCtrl, maxLines: 2, textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Description (optional)')),
                const SizedBox(height: 12),
                ref.watch(allCategoriesProvider).when(
                  data: (cats) => DropdownButtonFormField<int>(
                    value: _categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                    onChanged: (v) { if (v != null) setState(() => _categoryId = v); },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Could not load categories'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _quality,
                  decoration: const InputDecoration(labelText: 'Quality / condition'),
                  items: _qualityChoices.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                  onChanged: (v) { if (v != null) setState(() => _quality = v); },
                ),
                const SizedBox(height: 12),
                TextField(controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Price (ZMW)', hintText: '0.00')),
                const SizedBox(height: 12),
                TextField(controller: _stockCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stock quantity')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Variants
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Variants (optional)',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
                    TextButton.icon(
                      onPressed: () => setState(() => _variants.add(_VariantRow())),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                for (var i = 0; i < _variants.length; i++) ...[
                  const Divider(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Row(children: [
                              Expanded(child: TextField(controller: _variants[i].nameCtrl,
                                decoration: const InputDecoration(labelText: 'Name', hintText: 'Size'))),
                              const SizedBox(width: 8),
                              Expanded(child: TextField(controller: _variants[i].valueCtrl,
                                decoration: const InputDecoration(labelText: 'Value', hintText: 'XL'))),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(child: TextField(controller: _variants[i].skuCtrl,
                                decoration: const InputDecoration(labelText: 'SKU'))),
                              const SizedBox(width: 8),
                              Expanded(child: TextField(controller: _variants[i].stockCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Stock'))),
                            ]),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: AppTheme.error),
                        onPressed: () => setState(() { _variants[i].dispose(); _variants.removeAt(i); }),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _imgPlaceholder() {
    return Container(width: 100, height: 100, color: AppTheme.divider,
      child: const Icon(Icons.image_outlined, color: AppTheme.textSecondary));
  }
}
