import 'package:flutter/material.dart';
import 'package:pocketcrm/domain/models/company.dart';
import 'package:pocketcrm/domain/models/contact.dart';
import 'package:pocketcrm/domain/models/task.dart';
import 'package:pocketcrm/presentation/shared/dynamic_fields/dynamic_field_descriptor.dart';

class EntityFieldMetadata {
  static final List<DynamicFieldDescriptor<Contact>> contactList = [
    DynamicFieldDescriptor<Contact>(
      key: 'companyName',
      label: 'Company',
      icon: Icons.business,
      extractor: (c) => c.companyName,
    ),
    DynamicFieldDescriptor<Contact>(
      key: 'jobTitle',
      label: 'Job Title',
      icon: Icons.badge_outlined,
      extractor: (c) => c.jobTitle,
    ),
    DynamicFieldDescriptor<Contact>(
      key: 'city',
      label: 'City',
      icon: Icons.location_city_outlined,
      extractor: (c) => c.city,
    ),
    DynamicFieldDescriptor<Contact>(
      key: 'email',
      label: 'Email',
      icon: Icons.email_outlined,
      extractor: (c) => c.email,
    ),
    DynamicFieldDescriptor<Contact>(
      key: 'phone',
      label: 'Phone',
      icon: Icons.phone_outlined,
      extractor: (c) => c.phone,
    ),
  ];

  static final List<DynamicFieldDescriptor<Company>> companyList = [
    DynamicFieldDescriptor<Company>(
      key: 'domainName',
      label: 'Domain',
      icon: Icons.public,
      extractor: (c) => c.domainName,
    ),
    DynamicFieldDescriptor<Company>(
      key: 'industry',
      label: 'Industry',
      icon: Icons.category_outlined,
      extractor: (c) => c.industry,
    ),
    DynamicFieldDescriptor<Company>(
      key: 'employeesCount',
      label: 'Employees',
      icon: Icons.groups_outlined,
      extractor: (c) =>
          c.employeesCount != null ? '${c.employeesCount} employees' : null,
    ),
  ];

  static final List<DynamicFieldDescriptor<Task>> taskList = [
    DynamicFieldDescriptor<Task>(
      key: 'dueAt',
      label: 'Due date',
      icon: Icons.calendar_today_outlined,
      extractor: (t) => t.dueAt?.toLocal().toString().split('.').first,
    ),
    DynamicFieldDescriptor<Task>(
      key: 'contactName',
      label: 'Contact',
      icon: Icons.person_outline,
      extractor: (t) => t.contactName,
    ),
    DynamicFieldDescriptor<Task>(
      key: 'body',
      label: 'Details',
      icon: Icons.notes_outlined,
      extractor: (t) => t.bodyPlainText,
    ),
  ];
}
