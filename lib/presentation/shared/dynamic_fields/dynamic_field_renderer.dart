import 'package:flutter/material.dart';
import 'package:pocketcrm/presentation/shared/dynamic_fields/dynamic_field_descriptor.dart';

class DynamicFieldRenderer<T> extends StatelessWidget {
  final T entity;
  final List<DynamicFieldDescriptor<T>> descriptors;
  final int maxLines;
  final TextStyle? textStyle;
  final Color? iconColor;
  final double iconSize;

  const DynamicFieldRenderer({
    super.key,
    required this.entity,
    required this.descriptors,
    this.maxLines = 2,
    this.textStyle,
    this.iconColor,
    this.iconSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];

    for (final descriptor in descriptors) {
      if (!descriptor.visibleFor(entity)) continue;
      final raw = descriptor.extractor(entity)?.trim();
      if (raw == null || raw.isEmpty) continue;
      lines.add(
        Row(
          children: [
            Icon(
              descriptor.icon,
              size: iconSize,
              color:
                  iconColor ?? Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                raw,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle ?? Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
      if (lines.length >= maxLines) break;
    }

    if (lines.isEmpty) {
      return Text(
        'No details',
        style: textStyle ?? Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines
          .expand((line) => [line, const SizedBox(height: 4)])
          .toList()
        ..removeLast(),
    );
  }
}
