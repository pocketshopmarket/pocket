import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/review.dart';
import '../services/review_service.dart';

class ReviewState {
  final bool isLoading;
  final String? error;
  final double averageRating;
  final int reviewCount;
  final List<ProductReview> reviews;

  const ReviewState({
    this.isLoading = false,
    this.error,
    this.averageRating = 0,
    this.reviewCount = 0,
    this.reviews = const [],
  });

  ReviewState copyWith({
    bool? isLoading,
    String? error,
    double? averageRating,
    int? reviewCount,
    List<ProductReview>? reviews,
  }) {
    return ReviewState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      reviews: reviews ?? this.reviews,
    );
  }
}

class ReviewNotifier extends StateNotifier<ReviewState> {
  ReviewNotifier(this._service) : super(const ReviewState());

  final ReviewService _service;

  Future<void> load(int productId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _service.fetchProductReviews(productId);
      state = state.copyWith(
        isLoading: false,
        averageRating: result.averageRating,
        reviewCount: result.reviewCount,
        reviews: result.reviews,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<String?> submit({
    required int productId,
    required int rating,
    required String comment,
  }) async {
    try {
      await _service.submitReview(
        productId: productId,
        rating: rating,
        comment: comment,
      );
      await load(productId);
      return null;
    } catch (e) {
      return e.toString().replaceAll('Exception: ', '');
    }
  }
}

final reviewServiceProvider = Provider<ReviewService>((ref) => ReviewService());

final reviewProvider =
    StateNotifierProvider.autoDispose<ReviewNotifier, ReviewState>((ref) {
      return ReviewNotifier(ref.read(reviewServiceProvider));
    });
