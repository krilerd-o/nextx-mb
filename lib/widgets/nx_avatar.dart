import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/entity_display.dart';
import '../core/i18n.dart';

const _palette = <Color>[
  Color(0xFF6366F1),
  Color(0xFF0EA5E9),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
  Color(0xFFF97316),
];

Color nxAvatarColor(String seed) {
  var hash = 0;
  for (final u in seed.codeUnits) {
    hash = 0x1fffffff & (hash + u);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  return _palette[hash.abs() % _palette.length];
}

/// Profile photos of users seen so far (user id → absolute image URL), from
/// `imagename` in user lists — so cards can show the real photo.
final Map<String, String> nxUserPhotos = {};

/// Remembers the photo of each user row (`{id, imagename}`); [resolve] turns a
/// stored path into an absolute URL (the API client's `absoluteUrl`).
void nxRememberUserPhotos(Iterable<Map<String, dynamic>> users, String Function(String) resolve) {
  for (final u in users) {
    final id = '${u['id'] ?? ''}';
    final img = '${u['imagename'] ?? ''}'.trim();
    if (id.isEmpty || img.isEmpty || img == 'null') continue;
    final path = img.startsWith('http') || img.startsWith('/') ? img : (img.startsWith('uploads/') ? '/$img' : '/uploads/$img');
    nxUserPhotos[id] = resolve(path);
  }
}

/// [image] decoded at the size it is shown ([size] logical px × device pixel ratio) instead
/// of at the photo's full resolution — a 12-megapixel profile photo in a 46px circle was
/// decoded and kept in memory at full size.
ImageProvider nxSizedImage(BuildContext context, ImageProvider image, double size) {
  if (image is ResizeImage) return image;
  final px = (size * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0).clamp(1.0, 4.0)).round().clamp(16, 1024);
  return ResizeImage(image, width: px);
}

/// Avatar photo at [url]: kept on disk between launches (cached_network_image) and decoded
/// at its shown size (see [nxSizedImage]).
ImageProvider nxAvatarImage(BuildContext context, String url, double size) =>
    nxSizedImage(context, CachedNetworkImageProvider(url), size);

class NxAvatar extends StatelessWidget {
  const NxAvatar({
    super.key,
    required this.label,
    this.size = 44,
    this.imageUrl,
  });

  final String label;
  final double size;

  /// Profile photo; the initials stay underneath while it loads or if it fails.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final bg = nxAvatarColor(label);
    final url = imageUrl;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bg.withValues(alpha: 0.18),
      foregroundImage: url != null && url.startsWith('http') ? nxAvatarImage(context, url, size) : null,
      onForegroundImageError: url != null && url.startsWith('http') ? (_, __) {} : null,
      child: Text(
        tr(entityInitials(label)),
        style: TextStyle(
          color: bg,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}
