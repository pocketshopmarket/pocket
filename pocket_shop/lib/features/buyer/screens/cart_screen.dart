import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../widgets/product_list_thumbnail.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/cart_provider.dart';
import '../../../../providers/delivery_provider.dart';
import '../../../../models/order.dart';
import '../../../../providers/orders_provider.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  Future<void> _openCheckout(BuildContext context, WidgetRef ref) async {
    final user = ref.read(userProvider);
    final cartItems = ref.read(cartProvider).items;
    final defaultStore = cartItems.isNotEmpty
        ? (cartItems.first.product.sellerName ?? 'Seller store')
        : 'Seller store';
    final addressController = TextEditingController(
      text: user?.buyerProfile?.defaultAddress ?? '',
    );
    final notesController = TextEditingController();
    String fulfillmentType = 'delivery';
    bool useManualAddress = false;
    bool locating = false;
    bool quoteLoading = false;
    bool autoLocateTriggered = false;
    double? selectedLat;
    double? selectedLng;
    String? locationLabel;
    String? quoteError;
    double? quoteFee;
    double? quoteDistanceKm;
    int? quoteEtaMinutes;
    String pickupTimeSlot = 'As soon as possible';
    Timer? manualSearchDebounce;
    bool searchingAddress = false;
    List<Map<String, dynamic>> addressSuggestions = [];

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        int step = 1;
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (step == 1 &&
                fulfillmentType == 'delivery' &&
                !autoLocateTriggered) {
              autoLocateTriggered = true;
              Future<void>.microtask(() async {
                setModalState(() {
                  locating = true;
                });
                try {
                  final serviceEnabled =
                      await Geolocator.isLocationServiceEnabled();
                  if (!serviceEnabled) {
                    setModalState(() {
                      locating = false;
                    });
                    return;
                  }
                  var permission = await Geolocator.checkPermission();
                  if (permission == LocationPermission.denied) {
                    permission = await Geolocator.requestPermission();
                  }
                  if (permission == LocationPermission.denied ||
                      permission == LocationPermission.deniedForever) {
                    setModalState(() {
                      locating = false;
                    });
                    return;
                  }
                  final pos = await Geolocator.getCurrentPosition();
                  final svc = ref.read(deliveryServiceProvider);
                  String resolvedName =
                      '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
                  try {
                    final reverse = await svc.reverseGeocode(
                      lat: pos.latitude,
                      lng: pos.longitude,
                    );
                    final display = reverse?['display_name']?.toString().trim();
                    if (display != null && display.isNotEmpty) {
                      resolvedName = display;
                    }
                  } catch (_) {}
                  setModalState(() {
                    selectedLat = pos.latitude;
                    selectedLng = pos.longitude;
                    locationLabel = resolvedName;
                    locating = false;
                  });
                } catch (_) {
                  setModalState(() {
                    locating = false;
                  });
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Checkout',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step $step of 3',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (step == 1) ...[
                    const Text(
                      'Fulfillment method',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'delivery',
                          label: Text('Delivery'),
                          icon: Icon(Icons.local_shipping_outlined),
                        ),
                        ButtonSegment<String>(
                          value: 'pickup',
                          label: Text('Pickup'),
                          icon: Icon(Icons.storefront_outlined),
                        ),
                      ],
                      selected: {fulfillmentType},
                      onSelectionChanged: (selection) {
                        final next = selection.first;
                        setModalState(() {
                          fulfillmentType = next;
                          if (next == 'pickup') {
                            quoteError = null;
                            quoteFee = null;
                            quoteDistanceKm = null;
                            quoteEtaMinutes = null;
                            addressSuggestions = [];
                            searchingAddress = false;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (fulfillmentType == 'delivery') ...[
                      const Text(
                        'Delivery location',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              locationLabel ??
                                  'We will detect your location automatically.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: locating
                                  ? null
                                  : () async {
                                      setModalState(() {
                                        locating = true;
                                      });
                                      final serviceEnabled =
                                          await Geolocator.isLocationServiceEnabled();
                                      if (!serviceEnabled) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Turn on location services first',
                                            ),
                                          ),
                                        );
                                        setModalState(() {
                                          locating = false;
                                        });
                                        return;
                                      }
                                      var permission =
                                          await Geolocator.checkPermission();
                                      if (permission ==
                                          LocationPermission.denied) {
                                        permission =
                                            await Geolocator.requestPermission();
                                      }
                                      if (permission ==
                                              LocationPermission.denied ||
                                          permission ==
                                              LocationPermission
                                                  .deniedForever) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Location permission is required',
                                            ),
                                          ),
                                        );
                                        setModalState(() {
                                          locating = false;
                                        });
                                        return;
                                      }

                                      final pos =
                                          await Geolocator.getCurrentPosition();
                                      final svc = ref.read(
                                        deliveryServiceProvider,
                                      );
                                      String resolvedName =
                                          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
                                      try {
                                        final reverse = await svc
                                            .reverseGeocode(
                                              lat: pos.latitude,
                                              lng: pos.longitude,
                                            );
                                        final display = reverse?['display_name']
                                            ?.toString()
                                            .trim();
                                        if (display != null &&
                                            display.isNotEmpty) {
                                          resolvedName = display;
                                        }
                                      } catch (_) {}
                                      if (!context.mounted) return;
                                      setModalState(() {
                                        selectedLat = pos.latitude;
                                        selectedLng = pos.longitude;
                                        locationLabel = resolvedName;
                                        addressSuggestions = [];
                                        locating = false;
                                      });
                                    },
                              icon: const Icon(
                                Icons.my_location_rounded,
                                size: 18,
                              ),
                              label: Text(
                                locating
                                    ? 'Detecting...'
                                    : 'Use my current location',
                              ),
                            ),
                            TextButton(
                              onPressed: () => setModalState(() {
                                useManualAddress = !useManualAddress;
                                if (!useManualAddress) {
                                  addressSuggestions = [];
                                  searchingAddress = false;
                                }
                              }),
                              child: Text(
                                useManualAddress
                                    ? 'Use detected location'
                                    : 'Enter manually',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (useManualAddress) ...[
                        const SizedBox(height: 6),
                        TextField(
                          controller: addressController,
                          maxLines: 2,
                          onChanged: (value) {
                            manualSearchDebounce?.cancel();
                            final query = value.trim();
                            if (query.length < 3) {
                              setModalState(() {
                                searchingAddress = false;
                                addressSuggestions = [];
                              });
                              return;
                            }
                            setModalState(() {
                              searchingAddress = true;
                            });
                            manualSearchDebounce = Timer(
                              const Duration(milliseconds: 350),
                              () async {
                                try {
                                  final results = await ref
                                      .read(deliveryServiceProvider)
                                      .searchAddressSuggestions(
                                        query,
                                        limit: 5,
                                      );
                                  if (!context.mounted) return;
                                  setModalState(() {
                                    addressSuggestions = results;
                                    searchingAddress = false;
                                  });
                                } catch (_) {
                                  if (!context.mounted) return;
                                  setModalState(() {
                                    searchingAddress = false;
                                    addressSuggestions = [];
                                  });
                                }
                              },
                            );
                          },
                          decoration: InputDecoration(
                            hintText: 'Type area, street, or landmark',
                            filled: true,
                            fillColor: const Color(0xFFEEEEEE),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        if (searchingAddress)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(
                              color: AppTheme.primaryCyan,
                            ),
                          ),
                        if (addressSuggestions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: addressSuggestions.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final row = addressSuggestions[i];
                                final name =
                                    row['display_name']?.toString() ?? '';
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.location_on_outlined,
                                    size: 18,
                                    color: AppTheme.textSecondary,
                                  ),
                                  title: Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  onTap: () {
                                    final la = (row['lat'] as num?)?.toDouble();
                                    final ln = (row['lng'] as num?)?.toDouble();
                                    addressController.text = name;
                                    setModalState(() {
                                      locationLabel = name;
                                      selectedLat = la;
                                      selectedLng = ln;
                                      addressSuggestions = [];
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                      if (quoteError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          quoteError!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.warning,
                          ),
                        ),
                      ],
                    ] else ...[
                      const Text(
                        'Pickup details',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Pickup store: $defaultStore',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: pickupTimeSlot,
                        decoration: InputDecoration(
                          labelText: 'Pickup time',
                          filled: true,
                          fillColor: const Color(0xFFEEEEEE),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'As soon as possible',
                            child: Text('As soon as possible'),
                          ),
                          DropdownMenuItem(
                            value: 'In 30 minutes',
                            child: Text('In 30 minutes'),
                          ),
                          DropdownMenuItem(
                            value: 'In 1 hour',
                            child: Text('In 1 hour'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setModalState(() => pickupTimeSlot = value);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Notes (optional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Gate code, landmarks…',
                        filled: true,
                        fillColor: const Color(0xFFEEEEEE),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ] else if (step == 2) ...[
                    const Text(
                      'Order summary',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Payments are currently disabled. Orders are placed directly for fulfillment.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Review',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fulfillmentType == 'pickup'
                          ? 'Method: Pickup'
                          : 'Method: Delivery',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fulfillmentType == 'pickup'
                          ? 'Store: $defaultStore'
                          : 'Location: ${useManualAddress && addressController.text.trim().isNotEmpty ? addressController.text.trim() : (locationLabel ?? 'Unknown location')}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (fulfillmentType == 'pickup') ...[
                      const SizedBox(height: 4),
                      Text(
                        'Pickup time: $pickupTimeSlot',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                    if (fulfillmentType == 'delivery' && quoteFee != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Estimated delivery fee: ZMW ${quoteFee!.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (quoteDistanceKm != null)
                        Text(
                          'Distance: ${quoteDistanceKm!.toStringAsFixed(1)} km',
                          style: const TextStyle(fontSize: 13),
                        ),
                      if (quoteEtaMinutes != null)
                        Text(
                          'ETA: ~${quoteEtaMinutes!} min',
                          style: const TextStyle(fontSize: 13),
                        ),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      'Payment: currently disabled',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (quoteLoading) return;
                        if (step == 1) {
                          if (fulfillmentType == 'delivery') {
                            if (useManualAddress &&
                                addressController.text.trim().isEmpty) {
                              return;
                            }
                            if (selectedLat == null || selectedLng == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    useManualAddress
                                        ? 'Select one of the suggested addresses for precise routing.'
                                        : 'Please allow location to calculate delivery route.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setModalState(() {
                              quoteLoading = true;
                              quoteError = null;
                            });
                            ref
                                .read(deliveryServiceProvider)
                                .fetchQuote(
                                  deliveryLat: selectedLat!,
                                  deliveryLng: selectedLng!,
                                )
                                .then((quote) {
                                  if (!context.mounted) return;
                                  setModalState(() {
                                    quoteFee =
                                        (quote['fee'] as num?)?.toDouble() ??
                                        (quote['delivery_fee'] as num?)
                                            ?.toDouble();
                                    quoteDistanceKm =
                                        (quote['distance_km'] as num?)
                                            ?.toDouble();
                                    quoteEtaMinutes =
                                        (quote['eta_minutes'] as num?)?.toInt();
                                    quoteLoading = false;
                                    step = 2;
                                  });
                                })
                                .catchError((_) {
                                  if (!context.mounted) return;
                                  setModalState(() {
                                    quoteLoading = false;
                                    quoteError =
                                        'Could not fetch quote right now. You can still continue.';
                                    step = 2;
                                  });
                                });
                            return;
                          }
                          setModalState(() => step = 2);
                          return;
                        }
                        if (step == 2) {
                          setModalState(() => step = 3);
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      child: Text(
                        quoteLoading
                            ? 'Calculating route...'
                            : (step == 3 ? 'Place order' : 'Continue'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    manualSearchDebounce?.cancel();

    if (ok != true || !context.mounted) return;

    final result = await ref
        .read(cartProvider.notifier)
        .checkout(
          deliveryAddress: fulfillmentType == 'pickup'
              ? 'Pickup at $defaultStore'
              : (useManualAddress && addressController.text.trim().isNotEmpty
                    ? addressController.text
                    : (locationLabel ?? addressController.text)),
          specialInstructions: notesController.text,
          fulfillmentType: fulfillmentType,
          quotedDeliveryFee: quoteFee,
          quotedDistanceKm: quoteDistanceKm,
          quotedEtaMinutes: quoteEtaMinutes,
          deliveryLat: selectedLat,
          deliveryLng: selectedLng,
          pickupTimeSlot: fulfillmentType == 'pickup' ? pickupTimeSlot : null,
        );

    if (!context.mounted) return;

    if (result['success'] == true) {
      final order = result['order'] as Order?;
      final orderNumber = order?.orderNumber ?? '';
      ref.invalidate(buyerOrdersProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order placed successfully'),
          backgroundColor: AppTheme.success,
        ),
      );
      if (orderNumber.isNotEmpty && order?.isDelivery == true) {
        context.go(
          '/buyer/track-order?order=${Uri.encodeComponent(orderNumber)}',
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Checkout failed'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final showCheckoutBar =
        cartState.items.isNotEmpty &&
        !cartState.isLoading &&
        !cartState.isCheckingOut;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(title: const Text('My cart')),
      bottomNavigationBar: showCheckoutBar
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.divider.withValues(alpha: 0.8),
                    ),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 16,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'ZMW ${cartState.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${cartState.items.length} item(s) selected',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _openCheckout(context, ref),
                        child: const Text('Checkout'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cartState.isLoading && cartState.items.isEmpty)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                )
              else if (cartState.items.isEmpty) ...[
                const SizedBox(height: 32),
                Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.divider),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.shopping_cart_checkout_rounded,
                          size: 56,
                          color: AppTheme.textSecondary.withValues(alpha: 0.45),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Your cart is empty',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add items from Home to start your order.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary.withValues(
                              alpha: 0.9,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: FilledButton.icon(
                            onPressed: () => context.go('/buyer/home'),
                            icon: const Icon(Icons.storefront_outlined),
                            label: const Text('Start shopping'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: ListView.separated(
                    itemCount: cartState.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final item = cartState.items[index];
                      return Dismissible(
                        key: ValueKey(item.product.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss: (_) async {
                          final err = await cartNotifier.removeProduct(
                            item.product.id,
                          );
                          if (err != null && context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(err)));
                            return false;
                          }
                          return true;
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
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
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 76,
                                  height: 76,
                                  child: ProductListThumbnail(
                                    product: item.product,
                                    compactPlaceholder: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          'ZMW ${item.product.price.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.darkCyan,
                                          ),
                                        ),
                                        Text(
                                          'Each',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary
                                                .withValues(alpha: 0.9),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _qtyBtn(
                                          icon: Icons.remove,
                                          onTap: cartState.isLoading
                                              ? null
                                              : () async {
                                                  final err = await cartNotifier
                                                      .decreaseQuantity(
                                                        item.product.id,
                                                      );
                                                  if (err != null &&
                                                      context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(err),
                                                      ),
                                                    );
                                                  }
                                                },
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Text(
                                            '${item.quantity}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        _qtyBtn(
                                          icon: Icons.add,
                                          onTap: cartState.isLoading
                                              ? null
                                              : () async {
                                                  final err = await cartNotifier
                                                      .increaseQuantity(
                                                        item.product.id,
                                                      );
                                                  if (err != null &&
                                                      context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(err),
                                                      ),
                                                    );
                                                  }
                                                },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _qtyBtn({required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: AppTheme.surfaceWhite,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Icon(icon, size: 18, color: AppTheme.textPrimary),
        ),
      ),
    );
  }
}
