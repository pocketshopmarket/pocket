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
import '../../../../providers/payment_methods_provider.dart';

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
    String? quotePricingMode;
    String pickupTimeSlot = 'As soon as possible';
    String selectedProvider = 'AIRTEL_OAPI_ZMB';
    final payerNumberController = TextEditingController();
    Timer? manualSearchDebounce;
    bool searchingAddress = false;
    List<Map<String, dynamic>> addressSuggestions = [];

    String methodKeyForProvider(String providerCode) {
      switch (providerCode) {
        case 'MTN_MOMO_ZMB':
          return 'mtn_momo';
        case 'AIRTEL_OAPI_ZMB':
        case 'AIRTEL_MOMO_ZMB':
          return 'airtel_money';
        case 'ZAMTEL_MONEY_ZMB':
        case 'ZAMTEL_MOMO_ZMB':
          return 'zamtel';
        default:
          return 'mtn_momo';
      }
    }

    void syncNumberFromSavedMethods() {
      final methods = ref.read(paymentMethodsProvider);
      final key = methodKeyForProvider(selectedProvider);
      final matches = methods
          .where((m) => m.isVerified && m.provider == key)
          .toList()
        ..sort((a, b) => (b.isDefault ? 1 : 0).compareTo(a.isDefault ? 1 : 0));
      if (matches.isNotEmpty) {
        payerNumberController.text = matches.first.phoneNumber;
      } else {
        payerNumberController.clear();
      }
    }

    syncNumberFromSavedMethods();

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
              child: SingleChildScrollView(
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
                      'Payment method',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select mobile money provider',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _providerCard(
                                keyName: 'AIRTEL_OAPI_ZMB',
                                label: 'Airtel',
                                imageAsset: 'airtel.png',
                                selectedProvider: selectedProvider,
                                onTap: (value) => setModalState(() {
                                  selectedProvider = value;
                                  syncNumberFromSavedMethods();
                                }),
                              ),
                              _providerCard(
                                keyName: 'MTN_MOMO_ZMB',
                                label: 'MTN',
                                imageAsset: 'mtn.png',
                                selectedProvider: selectedProvider,
                                onTap: (value) => setModalState(() {
                                  selectedProvider = value;
                                  syncNumberFromSavedMethods();
                                }),
                              ),
                              _providerCard(
                                keyName: 'ZAMTEL_MONEY_ZMB',
                                label: 'Zamtel',
                                imageAsset: 'zamtel.png',
                                selectedProvider: selectedProvider,
                                onTap: (value) => setModalState(() {
                                  selectedProvider = value;
                                  syncNumberFromSavedMethods();
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: payerNumberController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Payer phone number',
                              hintText: 'e.g. 0973714666',
                              prefixText: '+260 ',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (_) {
                              final methods = ref.watch(paymentMethodsProvider);
                              final key = methodKeyForProvider(selectedProvider);
                              final hasVerified = methods.any(
                                (m) => m.isVerified && m.provider == key,
                              );
                              if (hasVerified) {
                                return const SizedBox.shrink();
                              }
                              if (payerNumberController.text.trim().isNotEmpty) {
                                return const SizedBox.shrink();
                              }
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 6),
                                child: Text(
                                  'Enter your mobile money number for this network.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.warning,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          ),
                          const Text(
                            'OTP/PIN authorization happens on customer phone via pawaPay.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
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
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryCyan.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primaryCyan.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_shipping_outlined,
                                  size: 16,
                                  color: AppTheme.primaryCyan,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Delivery fee',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryCyan,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  quotePricingMode == 'flat'
                                      ? 'Short trip (flat rate)'
                                      : quoteDistanceKm != null
                                          ? '${quoteDistanceKm!.toStringAsFixed(1)} km'
                                          : 'Distance-based',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                Text(
                                  'ZMW ${quoteFee!.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            if (quoteEtaMinutes != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Estimated arrival: ~${quoteEtaMinutes!} min',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment: ${selectedProvider == "AIRTEL_OAPI_ZMB" ? "Airtel" : selectedProvider == "MTN_MOMO_ZMB" ? "MTN" : "Zamtel"} Mobile Money',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          payerNumberController.text.trim().isEmpty ? 'Number not entered' : payerNumberController.text.trim(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Items subtotal',
                                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                              ),
                              Text(
                                'ZMW ${ref.read(cartProvider).totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (fulfillmentType == 'delivery') ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Delivery fee',
                                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                                ),
                                Text(
                                  quoteFee != null ? 'ZMW ${quoteFee!.toStringAsFixed(2)}' : 'Calculating...',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total to pay',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                'ZMW ${(ref.read(cartProvider).totalAmount + (fulfillmentType == 'delivery' ? (quoteFee ?? 0) : 0)).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (step > 1) ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                          ),
                          onPressed: () => setModalState(() => step--),
                          child: const Text('Back'),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: (step == 1 && fulfillmentType == 'delivery' && (selectedLat == null || selectedLng == null)) || quoteLoading ? null : () {
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
                            final sellerId = cartItems.isNotEmpty
                                ? cartItems.first.product.sellerId
                                : null;
                            ref
                                .read(deliveryServiceProvider)
                                .fetchQuote(
                                  deliveryLat: selectedLat!,
                                  deliveryLng: selectedLng!,
                                  sellerId: sellerId,
                                )
                                .then((quote) {
                                  if (!context.mounted) return;
                                  setModalState(() {
                                    quoteFee =
                                        (quote['estimated_fee_zmw'] as num?)
                                            ?.toDouble() ??
                                        (quote['fee'] as num?)?.toDouble();
                                    quoteDistanceKm =
                                        (quote['distance_km'] as num?)
                                            ?.toDouble();
                                    quotePricingMode =
                                        quote['pricing_mode']?.toString();
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
                          if (payerNumberController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please enter your mobile money number to continue.',
                                ),
                              ),
                            );
                            return;
                          }
                          // Normalize number: ensure it starts with +260
                          var num = payerNumberController.text.trim();
                          num = num.replaceAll(RegExp(r'[\s\-()]'), '');
                          if (num.startsWith('0')) {
                            num = '+260${num.substring(1)}';
                          } else if (!num.startsWith('+')) {
                            num = '+260$num';
                          }
                          payerNumberController.text = num;
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
            ],
          ),
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
          paymentProvider: selectedProvider,
          payerNumber: payerNumberController.text,
        );

    if (!context.mounted) return;

    if (result['success'] == true) {
      final order = result['order'] as Order?;
      final orderNumber = order?.orderNumber ?? '';
      final payment = result['payment'] as Map<String, dynamic>?;
      ref.invalidate(buyerOrdersProvider);

      if (orderNumber.isNotEmpty) {
        // Navigate to payment pending screen so buyer can track payment status
        final amountCharged = payment?['amount_charged']?.toString() ?? '';
        context.go(
          '/buyer/payment-pending'
          '?order=${Uri.encodeComponent(orderNumber)}'
          '&provider=${Uri.encodeComponent(selectedProvider)}'
          '&amount=${Uri.encodeComponent(amountCharged)}'
          '&delivery=${order?.isDelivery == true ? 'true' : 'false'}',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order placed successfully'),
            backgroundColor: AppTheme.success,
          ),
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
    payerNumberController.dispose();
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
                          'Items subtotal',
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
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Delivery fee',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          'Calculated at checkout',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryCyan,
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

  Widget _providerCard({
    required String keyName,
    required String label,
    required String imageAsset,
    required String selectedProvider,
    required ValueChanged<String> onTap,
  }) {
    final selected = keyName == selectedProvider;
    return InkWell(
      onTap: () => onTap(keyName),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.lightCyan : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primaryCyan : AppTheme.divider,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 32,
              child: Image.asset(
                imageAsset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.sim_card_rounded),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
