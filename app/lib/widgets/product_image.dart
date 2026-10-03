import 'package:flutter/material.dart';
import '../core/config.dart';
import '../core/theme/app_colors.dart';

/// The one widget used to render a product image everywhere — catalog card,
/// product page, cart, checkout, order detail, payment review, POS, inventory
/// and stock movements — so the same image reference renders the same way
/// (and the same fallback shows when a product has no photo).
class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.size,
    this.width,
    this.height,
    this.radius = 8,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final url = imageUrl;
    final placeholderSize = ((w ?? h ?? 48) * 0.45).clamp(16.0, 48.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: w,
        height: h,
        color: AppColors.surface,
        alignment: Alignment.center,
        child: url == null || url.isEmpty
            ? Icon(Icons.inventory_2_outlined, size: placeholderSize, color: AppColors.textSecondary)
            : Image.network(
                AppConfig.resolveMediaUrl(url),
                fit: fit,
                width: w,
                height: h,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                errorBuilder: (context, error, stack) =>
                    Icon(Icons.broken_image_outlined, size: placeholderSize, color: AppColors.textSecondary),
              ),
      ),
    );
  }
}

/// Opens the image full-screen (used for receipts and product photos).
Future<void> showImageViewer(BuildContext context, String url, {String? title}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: 16),
              Expanded(child: Text(title ?? 'Preview', style: Theme.of(ctx).textTheme.titleMedium)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ],
          ),
          Flexible(
            child: InteractiveViewer(
              child: Image.network(
                AppConfig.resolveMediaUrl(url),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Could not load the file. It may be a PDF — open it from the link instead.'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
