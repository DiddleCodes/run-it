/// How the Home vendor list is ordered — mirrors the backend's
/// `GET /vendors?sort=` values.
enum VendorSort {
  name('name', 'A–Z'),
  rating('rating', 'Top rated');

  const VendorSort(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// The Home screen's filter sheet (the slider icon in the search bar).
/// Every option is applied by the backend against real data — vendor
/// ratings and menu prices — never filtered or faked client-side.
class VendorFilters {
  const VendorFilters({this.sort = VendorSort.name, this.minRating, this.maxPriceNaira});

  final VendorSort sort;

  /// Only vendors rated at least this (unrated vendors never match).
  final double? minRating;

  /// Only vendors with an available item at or under this price.
  final int? maxPriceNaira;

  static const ratingOptions = [4.0, 4.5];
  static const priceOptions = [1000, 2000, 3000];

  /// How many filters differ from the defaults — the badge on the icon.
  int get activeCount => (sort != VendorSort.name ? 1 : 0) + (minRating != null ? 1 : 0) + (maxPriceNaira != null ? 1 : 0);

  bool get isDefault => activeCount == 0;

  VendorFilters copyWith({VendorSort? sort, double? Function()? minRating, int? Function()? maxPriceNaira}) =>
      VendorFilters(
        sort: sort ?? this.sort,
        minRating: minRating != null ? minRating() : this.minRating,
        maxPriceNaira: maxPriceNaira != null ? maxPriceNaira() : this.maxPriceNaira,
      );

  @override
  bool operator ==(Object other) =>
      other is VendorFilters &&
      other.sort == sort &&
      other.minRating == minRating &&
      other.maxPriceNaira == maxPriceNaira;

  @override
  int get hashCode => Object.hash(sort, minRating, maxPriceNaira);
}
