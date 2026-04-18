import 'package:flutter/material.dart';

typedef DynamicValueExtractor<T> = String? Function(T entity);
typedef DynamicValueVisibility<T> = bool Function(T entity);

class DynamicFieldDescriptor<T> {
  final String key;
  final String label;
  final IconData icon;
  final DynamicValueExtractor<T> extractor;
  final DynamicValueVisibility<T>? isVisible;

  const DynamicFieldDescriptor({
    required this.key,
    required this.label,
    required this.icon,
    required this.extractor,
    this.isVisible,
  });

  bool visibleFor(T entity) => isVisible == null || isVisible!(entity);
}
