enum ViewMode {
  list,
  table,
}

extension ViewModeStorage on ViewMode {
  String get storageValue => name;

  static ViewMode fromStorageValue(String? value) {
    if (value == ViewMode.table.name) return ViewMode.table;
    return ViewMode.list;
  }
}

