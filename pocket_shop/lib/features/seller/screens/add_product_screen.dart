import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/category_provider.dart';
import '../../../providers/product_provider.dart';
import '../../../services/product_service.dart';

const int _kMaxProductImages = 5;

class _PendingImage {
  _PendingImage({required this.bytes, this.filePath, required this.filename});

  final Uint8List bytes;
  final String? filePath;
  final String filename;
}

class _VariantDraft {
  _VariantDraft();

  final TextEditingController name = TextEditingController();
  final TextEditingController value = TextEditingController();
  final TextEditingController sku = TextEditingController();
  final TextEditingController stock = TextEditingController(text: '0');

  void dispose() {
    name.dispose();
    value.dispose();
    sku.dispose();
    stock.dispose();
  }
}

class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({super.key});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  final List<_PendingImage> _images = [];
  final List<_VariantDraft> _variants = [];
  String _quality = 'new';
  int? _selectedCategoryId;

  static const List<(String value, String label)> _qualityChoices = [
    ('new', 'New'),
    ('like_new', 'Like new'),
    ('good', 'Good'),
    ('fair', 'Fair'),
    ('used', 'Used'),
  ];

  bool get _useDesktopFilePicker =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    for (final variant in _variants) {
      variant.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImagesWithFilePicker() async {
    final room = _kMaxProductImages - _images.length;
    if (room <= 0) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;
      var added = 0;
      for (final f in result.files) {
        if (_images.length >= _kMaxProductImages) break;
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final name = f.name.isNotEmpty ? f.name : 'product.jpg';
        setState(() {
          _images.add(_PendingImage(bytes: bytes, filename: name));
          added++;
        });
      }
      if (added == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read images. Try smaller files.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not pick images: $e')));
    }
  }

  Future<void> _pickOneImage(ImageSource source) async {
    if (_images.length >= _kMaxProductImages) return;
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 88,
      );
      if (!mounted) return;
      if (x != null) {
        final bytes = await x.readAsBytes();
        final path = kIsWeb ? null : x.path;
        setState(() {
          _images.add(
            _PendingImage(
              bytes: bytes,
              filePath: (path != null && path.isNotEmpty) ? path : null,
              filename: x.name.isNotEmpty ? x.name : 'product.jpg',
            ),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
    }
  }

  void _showImageSourceSheet() {
    if (_images.length >= _kMaxProductImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can add at most $_kMaxProductImages photos per product.',
          ),
        ),
      );
      return;
    }
    if (_useDesktopFilePicker) {
      _pickImagesWithFilePicker();
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickOneImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickOneImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty ||
        _priceController.text.trim().isEmpty ||
        _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name, price, and category are required.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final uploads = _images
        .map(
          (p) => ProductImageUpload(
            path: p.filePath,
            bytes: p.bytes,
            filename: p.filename,
          ),
        )
        .toList();
    final variants = _variants
        .map(
          (row) => {
            'name': row.name.text.trim(),
            'value': row.value.text.trim(),
            'sku': row.sku.text.trim(),
            'stock_quantity': int.tryParse(row.stock.text.trim()) ?? 0,
          },
        )
        .where(
          (row) =>
              row['name'].toString().isNotEmpty &&
              row['value'].toString().isNotEmpty &&
              row['sku'].toString().isNotEmpty,
        )
        .toList();

    final result = await ref
        .read(productProvider.notifier)
        .addProduct(
          name: _nameController.text.trim(),
          price: double.tryParse(_priceController.text.trim()) ?? 0.0,
          stockQuantity: int.tryParse(_stockController.text.trim()) ?? 1,
          description: _descriptionController.text.trim(),
          category: _selectedCategoryId.toString(),
          quality: _quality,
          images: uploads,
          variants: variants,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product added successfully'),
          backgroundColor: AppTheme.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Failed to add'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        title: const Text('Add product'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create product listing',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Add clear details so buyers can trust and buy quickly.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFD1D5DB)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photos (optional, up to $_kMaxProductImages)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < _images.length; i++)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  _images[i].bytes,
                                  width: 108,
                                  height: 108,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: IconButton.filled(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    padding: const EdgeInsets.all(4),
                                    minimumSize: const Size(32, 32),
                                  ),
                                  onPressed: () =>
                                      setState(() => _images.removeAt(i)),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (_images.length < _kMaxProductImages)
                          Material(
                            color: AppTheme.lightCyan.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _showImageSourceSheet,
                              child: const SizedBox(
                                width: 108,
                                height: 108,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 32,
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Add',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              child: Column(
                children: [
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Product name',
                      hintText: 'e.g. Fresh tomatoes 1kg',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'Short note for buyers',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Builder(builder: (context) {
                    final categories = ref.watch(allCategoriesProvider);
                    if (categories.isEmpty) {
                      return const LinearProgressIndicator();
                    }
                    return DropdownButtonFormField<int>(
                      initialValue: _selectedCategoryId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: categories
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedCategoryId = v);
                      },
                    );
                  }),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _quality,
                    decoration: const InputDecoration(
                      labelText: 'Quality / condition',
                    ),
                    items: _qualityChoices
                        .map(
                          (e) =>
                              DropdownMenuItem(value: e.$1, child: Text(e.$2)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _quality = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Price (ZMW)',
                      hintText: '0.00',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _stockController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stock quantity',
                      hintText: '1',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Variants (optional)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _variants.add(_VariantDraft());
                        }),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  if (_variants.isEmpty)
                    const Text(
                      'No variants added. Leave empty for a single-stock product.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ..._variants.asMap().entries.map((entry) {
                    final index = entry.key;
                    final row = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: row.name,
                                  decoration: const InputDecoration(
                                    labelText: 'Name',
                                    hintText: 'Size',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: row.value,
                                  decoration: const InputDecoration(
                                    labelText: 'Value',
                                    hintText: 'XL',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: row.sku,
                                  decoration: const InputDecoration(
                                    labelText: 'SKU',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: row.stock,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Stock',
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => setState(() {
                                  final target = _variants.removeAt(index);
                                  target.dispose();
                                }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _handleSave,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save product'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
