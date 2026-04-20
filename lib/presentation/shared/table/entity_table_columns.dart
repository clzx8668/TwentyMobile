import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pocketcrm/domain/models/company.dart';
import 'package:pocketcrm/domain/models/contact.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/presentation/shared/table/table_view.dart';

class TableColumnInfo {
  const TableColumnInfo({required this.key, required this.label});

  final String key;
  final String label;
}

const contactTableColumnInfos = <TableColumnInfo>[
  TableColumnInfo(key: 'name', label: 'Name'),
  TableColumnInfo(key: 'company', label: 'Company'),
  TableColumnInfo(key: 'jobTitle', label: 'Job Title'),
  TableColumnInfo(key: 'city', label: 'City'),
  TableColumnInfo(key: 'email', label: 'Email'),
  TableColumnInfo(key: 'phone', label: 'Phone'),
  TableColumnInfo(key: 'updatedAt', label: 'Updated'),
];

const companyTableColumnInfos = <TableColumnInfo>[
  TableColumnInfo(key: 'name', label: 'Name'),
  TableColumnInfo(key: 'domain', label: 'Domain'),
  TableColumnInfo(key: 'industry', label: 'Industry'),
  TableColumnInfo(key: 'employees', label: 'Employees'),
  TableColumnInfo(key: 'linkedin', label: 'LinkedIn'),
  TableColumnInfo(key: 'x', label: 'X'),
  TableColumnInfo(key: 'createdAt', label: 'Created'),
];

const taskTableColumnInfos = <TableColumnInfo>[
  TableColumnInfo(key: 'title', label: 'Title'),
  TableColumnInfo(key: 'status', label: 'Status'),
  TableColumnInfo(key: 'dueAt', label: 'Due'),
  TableColumnInfo(key: 'contact', label: 'Contact'),
  TableColumnInfo(key: 'createdAt', label: 'Created'),
];

List<TableColumnInfo> tableColumnInfosForEntity(String entity) {
  switch (entity) {
    case 'contacts':
      return contactTableColumnInfos;
    case 'companies':
      return companyTableColumnInfos;
    case 'tasks':
      return taskTableColumnInfos;
  }
  return const [];
}

String _fmtDateTime(DateTime? dt) {
  if (dt == null) return '';
  return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
}

List<TableColumnDef<Contact>> contactColumnsByKeys(List<String> keys) {
  final map = <String, TableColumnDef<Contact>>{
    'name': TableColumnDef<Contact>(
      key: 'name',
      label: 'Name',
      width: 170,
      cellBuilder: (_, c) => Text('${c.firstName} ${c.lastName}'.trim()),
      filterValueGetter: (c) => '${c.firstName} ${c.lastName}'.trim(),
      sortValueGetter: (c) =>
          '${c.firstName} ${c.lastName}'.trim().toLowerCase(),
    ),
    'company': TableColumnDef<Contact>(
      key: 'company',
      label: 'Company',
      width: 140,
      cellBuilder: (_, c) => Text(c.companyName ?? ''),
      filterValueGetter: (c) => c.companyName ?? '',
      sortValueGetter: (c) => (c.companyName ?? '').toLowerCase(),
    ),
    'email': TableColumnDef<Contact>(
      key: 'email',
      label: 'Email',
      width: 220,
      cellBuilder: (_, c) => Text(c.email ?? ''),
      filterValueGetter: (c) => c.email ?? '',
      sortValueGetter: (c) => (c.email ?? '').toLowerCase(),
    ),
    'phone': TableColumnDef<Contact>(
      key: 'phone',
      label: 'Phone',
      width: 160,
      cellBuilder: (_, c) => Text(c.phone ?? ''),
      filterValueGetter: (c) => c.phone ?? '',
      sortValueGetter: (c) => (c.phone ?? '').toLowerCase(),
    ),
    'jobTitle': TableColumnDef<Contact>(
      key: 'jobTitle',
      label: 'Job Title',
      width: 180,
      cellBuilder: (_, c) => Text(c.jobTitle ?? ''),
      filterValueGetter: (c) => c.jobTitle ?? '',
      sortValueGetter: (c) => (c.jobTitle ?? '').toLowerCase(),
    ),
    'city': TableColumnDef<Contact>(
      key: 'city',
      label: 'City',
      width: 150,
      cellBuilder: (_, c) => Text(c.city ?? ''),
      filterValueGetter: (c) => c.city ?? '',
      sortValueGetter: (c) => (c.city ?? '').toLowerCase(),
    ),
    'updatedAt': TableColumnDef<Contact>(
      key: 'updatedAt',
      label: 'Updated',
      width: 170,
      cellBuilder: (_, c) => Text(_fmtDateTime(c.updatedAt)),
      filterValueGetter: (c) => _fmtDateTime(c.updatedAt),
      sortValueGetter: (c) => c.updatedAt,
    ),
  };
  return keys
      .where(map.containsKey)
      .map((k) => map[k]!)
      .toList(growable: false);
}

List<TableColumnDef<Company>> companyColumnsByKeys(List<String> keys) {
  final map = <String, TableColumnDef<Company>>{
    'name': TableColumnDef<Company>(
      key: 'name',
      label: 'Name',
      width: 190,
      cellBuilder: (_, c) => Text(c.name),
      filterValueGetter: (c) => c.name,
      sortValueGetter: (c) => c.name.toLowerCase(),
    ),
    'domain': TableColumnDef<Company>(
      key: 'domain',
      label: 'Domain',
      width: 180,
      cellBuilder: (_, c) => Text(c.domainName ?? ''),
      filterValueGetter: (c) => c.domainName ?? '',
      sortValueGetter: (c) => (c.domainName ?? '').toLowerCase(),
    ),
    'industry': TableColumnDef<Company>(
      key: 'industry',
      label: 'Industry',
      width: 170,
      cellBuilder: (_, c) => Text(c.industry ?? ''),
      filterValueGetter: (c) => c.industry ?? '',
      sortValueGetter: (c) => (c.industry ?? '').toLowerCase(),
    ),
    'employees': TableColumnDef<Company>(
      key: 'employees',
      label: 'Employees',
      numeric: true,
      width: 120,
      cellBuilder: (_, c) => Text(c.employeesCount?.toString() ?? ''),
      filterValueGetter: (c) => c.employeesCount?.toString() ?? '',
      sortValueGetter: (c) => c.employeesCount,
    ),
    'linkedin': TableColumnDef<Company>(
      key: 'linkedin',
      label: 'LinkedIn',
      width: 220,
      cellBuilder: (_, c) => Text(c.linkedinUrl ?? ''),
      filterValueGetter: (c) => c.linkedinUrl ?? '',
      sortValueGetter: (c) => (c.linkedinUrl ?? '').toLowerCase(),
    ),
    'x': TableColumnDef<Company>(
      key: 'x',
      label: 'X',
      width: 170,
      cellBuilder: (_, c) => Text(c.xUrl ?? ''),
      filterValueGetter: (c) => c.xUrl ?? '',
      sortValueGetter: (c) => (c.xUrl ?? '').toLowerCase(),
    ),
    'createdAt': TableColumnDef<Company>(
      key: 'createdAt',
      label: 'Created',
      width: 170,
      cellBuilder: (_, c) => Text(_fmtDateTime(c.createdAt)),
      filterValueGetter: (c) => _fmtDateTime(c.createdAt),
      sortValueGetter: (c) => c.createdAt,
    ),
  };
  return keys
      .where(map.containsKey)
      .map((k) => map[k]!)
      .toList(growable: false);
}

Color _statusColor(BuildContext context, Task t) {
  if (t.completed == true) return Colors.green;
  if (t.dueAt != null && t.dueAt!.isBefore(DateTime.now())) {
    return Theme.of(context).colorScheme.error;
  }
  return Theme.of(context).colorScheme.primary;
}

List<TableColumnDef<Task>> taskColumnsByKeys(List<String> keys) {
  final map = <String, TableColumnDef<Task>>{
    'title': TableColumnDef<Task>(
      key: 'title',
      label: 'Title',
      width: 240,
      cellBuilder: (_, t) => Text(t.title),
      filterValueGetter: (t) => t.title,
      sortValueGetter: (t) => t.title.toLowerCase(),
    ),
    'status': TableColumnDef<Task>(
      key: 'status',
      label: 'Status',
      width: 120,
      cellBuilder: (ctx, t) => Text(
        (t.completed ?? false) ? 'DONE' : 'TODO',
        style: TextStyle(
          color: _statusColor(ctx, t),
          fontWeight: FontWeight.w600,
        ),
      ),
      filterValueGetter: (t) => (t.completed ?? false) ? 'DONE' : 'TODO',
      sortValueGetter: (t) => (t.completed ?? false) ? 1 : 0,
    ),
    'dueAt': TableColumnDef<Task>(
      key: 'dueAt',
      label: 'Due',
      width: 170,
      cellBuilder: (_, t) => Text(_fmtDateTime(t.dueAt)),
      filterValueGetter: (t) => _fmtDateTime(t.dueAt),
      sortValueGetter: (t) => t.dueAt,
    ),
    'contact': TableColumnDef<Task>(
      key: 'contact',
      label: 'Contact',
      width: 170,
      cellBuilder: (_, t) => Text(t.contactName ?? ''),
      filterValueGetter: (t) => t.contactName ?? '',
      sortValueGetter: (t) => (t.contactName ?? '').toLowerCase(),
    ),
    'createdAt': TableColumnDef<Task>(
      key: 'createdAt',
      label: 'Created',
      width: 170,
      cellBuilder: (_, t) => Text(_fmtDateTime(t.createdAt)),
      filterValueGetter: (t) => _fmtDateTime(t.createdAt),
      sortValueGetter: (t) => t.createdAt,
    ),
  };
  return keys
      .where(map.containsKey)
      .map((k) => map[k]!)
      .toList(growable: false);
}
