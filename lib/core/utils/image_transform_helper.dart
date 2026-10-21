// lib/core/utils/image_transform_helper.dart
// Image Transformation Helper: converts raw photo URLs to optimized WebP thumbnails

/// Transforms an image URL to a resized, WebP-compressed image.
/// - Lists: width 96, quality 75, WebP
/// - Detail / Hero: width 384, quality 75, WebP
String transformImageUrl(String originalUrl, {required int width, int quality = 75}) {
  if (!originalUrl.startsWith('http://') && !originalUrl.startsWith('https://')) {
    return originalUrl;
  }

  try {
    final uri = Uri.parse(originalUrl);

    // If Supabase Storage public object URL, route to Supabase Image Render Transform
    if (uri.path.contains('/storage/v1/object/public/')) {
      final renderPath = uri.path.replaceFirst('/storage/v1/object/public/', '/storage/v1/render/image/public/');
      final queryParams = Map<String, String>.from(uri.queryParameters);
      queryParams['width'] = width.toString();
      queryParams['quality'] = quality.toString();
      queryParams['format'] = 'webp';
      queryParams['resize'] = 'cover';
      return uri.replace(path: renderPath, queryParameters: queryParams).toString();
    }

    // Generic CDN or already transformed URL
    final queryParams = Map<String, String>.from(uri.queryParameters);
    queryParams['width'] = width.toString();
    queryParams['quality'] = quality.toString();
    queryParams['format'] = 'webp';
    return uri.replace(queryParameters: queryParams).toString();
  } catch (_) {
    return originalUrl;
  }
}
