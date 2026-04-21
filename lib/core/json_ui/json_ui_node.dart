class JsonUiNode {
  JsonUiNode({
    required this.type,
    Map<String, dynamic>? props,
    List<JsonUiNode>? children,
  })  : props = props ?? <String, dynamic>{},
        children = children ?? <JsonUiNode>[];

  final String type;
  final Map<String, dynamic> props;
  final List<JsonUiNode> children;

  factory JsonUiNode.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw Exception('JsonUiNode.type is required');
    }
    final props = json['props'] is Map
        ? Map<String, dynamic>.from(json['props'] as Map)
        : <String, dynamic>{};
    final rawChildren = json['children'];
    final children = <JsonUiNode>[];
    if (rawChildren is List) {
      for (final c in rawChildren) {
        if (c is Map) {
          children.add(JsonUiNode.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }
    return JsonUiNode(type: type, props: props, children: children);
  }
}

