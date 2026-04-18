import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pocketcrm/domain/models/company.dart';
import 'package:pocketcrm/domain/models/contact.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/presentation/shared/table/table_view.dart';

String _fmtDateTime(DateTime? dt) {
  if (dt == null) return '';
  return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
}

List<TableColumnDef<Contact>> contactColumnsByKeys(List<String> keys) {
  final map = <String, TableColumnDef<Contact>>{
    'name': TableColumnDef<Contact>(
      key: 'name',
      label: 'Name',
      cellBuilder: (_, c) => Text('${c.firstName} ${c.lastName}'.trim()),
    ),
    'company': TableColumnDef<Contact>(
      key: 'company',
      label: 'Company',
      cellBuilder: (_, c) => Text(c.companyName ?? ''),
    ),
    'email': TableColumnDef<Contact>(
      key: 'email',
      label: 'Email',
      cellBuilder: (_, c) => Text(c.email ?? ''),
    ),
    'phone': TableColumnDef<Contact>(
      key: 'phone',
      label: 'Phone',
      cellBuilder: (_, c) => Text(c.phone ?? ''),
    ),
    'jobTitle': TableColumnDef<Contact>(
      key: 'jobTitle',
      label: 'Job Title',
      cellBuilder: (_, c) => Text(c.jobTitle ?? ''),
    ),
    'city': TableColumnDef<Contact>(
      key: 'city',
      label: 'City',
      cellBuilder: (_, c) => Text(c.city ?? ''),
    ),
    'updatedAt': TableColumnDef<Contact>(
      key: 'updatedAt',
      label: 'Updated',
      cellBuilder: (_, c) => Text(_fmtDateTime(c.updatedAt)),
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
      cellBuilder: (_, c) => Text(c.name),
    ),
    'domain': TableColumnDef<Company>(
      key: 'domain',
      label: 'Domain',
      cellBuilder: (_, c) => Text(c.domainName ?? ''),
    ),
    'industry': TableColumnDef<Company>(
      key: 'industry',
      label: 'Industry',
      cellBuilder: (_, c) => Text(c.industry ?? ''),
    ),
    'employees': TableColumnDef<Company>(
      key: 'employees',
      label: 'Employees',
      numeric: true,
      cellBuilder: (_, c) => Text(c.employeesCount?.toString() ?? ''),
    ),
    'linkedin': TableColumnDef<Company>(
      key: 'linkedin',
      label: 'LinkedIn',
      cellBuilder: (_, c) => Text(c.linkedinUrl ?? ''),
    ),
    'x': TableColumnDef<Company>(
      key: 'x',
      label: 'X',
      cellBuilder: (_, c) => Text(c.xUrl ?? ''),
    ),
    'createdAt': TableColumnDef<Company>(
      key: 'createdAt',
      label: 'Created',
      cellBuilder: (_, c) => Text(_fmtDateTime(c.createdAt)),
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
      cellBuilder: (_, t) => Text(t.title),
    ),
    'status': TableColumnDef<Task>(
      key: 'status',
      label: 'Status',
      cellBuilder: (ctx, t) => Text(
        (t.completed ?? false) ? 'DONE' : 'TODO',
        style: TextStyle(color: _statusColor(ctx, t), fontWeight: FontWeight.w600),
      ),
    ),
    'dueAt': TableColumnDef<Task>(
      key: 'dueAt',
      label: 'Due',
      cellBuilder: (_, t) => Text(_fmtDateTime(t.dueAt)),
    ),
    'contact': TableColumnDef<Task>(
      key: 'contact',
      label: 'Contact',
      cellBuilder: (_, t) => Text(t.contactName ?? ''),
    ),
    'createdAt': TableColumnDef<Task>(
      key: 'createdAt',
      label: 'Created',
      cellBuilder: (_, t) => Text(_fmtDateTime(t.createdAt)),
    ),
  };
  return keys
      .where(map.containsKey)
      .map((k) => map[k]!)
      .toList(growable: false);
}

