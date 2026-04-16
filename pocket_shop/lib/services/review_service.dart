import '../core/constants/app_constants.dart';
import '../models/review.dart';
import 'api_service.dart';

class ReviewSummary {
  final double averageRating;
  final int reviewCount;
  final List<ProductReview> reviews;

  const ReviewSummary({
    required this.averageRating,
    required this.reviewCount,
    required this.reviews,
  });
}

class ReviewService {
  final ApiService _api = ApiService();

  Future<ReviewSummary> fetchProductReviews(int productId) async {
    final response = await _api.get('${AppConstants.reviewsEndpoint}$productId/');
    final data = response.data as Map<String, dynamic>;
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final rows = data['results'] as List? ?? [];
    return ReviewSummary(
      averageRating: (summary['average_rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (summary['review_count'] as num?)?.toInt() ?? 0,
      reviews: rows
          .map((e) => ProductReview.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<ProductReview> submitReview({
    required int productId,
    required int rating,
    required String comment,
  }) async {
    final response = await _api.post(
      '${AppConstants.reviewsEndpoint}$productId/',
      data: {'rating': rating, 'comment': comment},
    );
    return ProductReview.fromJson(response.data as Map<String, dynamic>);
  }
}
