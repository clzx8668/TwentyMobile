import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/domain/models/company.dart';
import 'package:pocketcrm/presentation/shared/snackbar_helper.dart';
import 'package:pocketcrm/core/utils/demo_utils.dart';
import 'dart:async';
import 'package:pocketcrm/core/json_ui/json_ui_node.dart';
import 'package:pocketcrm/core/json_ui/json_ui_renderer.dart';
import 'package:pocketcrm/presentation/shared/json_ui_host.dart';
import 'package:pocketcrm/presentation/shared/view_mode_toggle_button.dart';

class CompaniesScreen extends ConsumerStatefulWidget {
  const CompaniesScreen({super.key});

  @override
  ConsumerState<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends ConsumerState<CompaniesScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(companiesProvider.notifier).search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search companies...',
            prefixIcon: const Icon(Icons.search),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Colors.white,
          ),
          onChanged: _onSearchChanged,
        ),
        actions: const [
          ViewModeToggleButton(pageKey: 'companies'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (!await DemoUtils.checkDemoAction(context, ref)) return;
          if (!context.mounted) return;
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => const AddCompanySheet(),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: JsonUiHost(
        pageKey: 'companies',
        ui: JsonUiBuildContext(pageKey: 'companies'),
        fallbackNode: JsonUiNode(
          type: 'entity_list',
          props: {
            'entity': 'companies',
            'tableColumns': const [
              'name',
              'domain',
              'industry',
              'employees',
              'linkedin',
              'x',
              'createdAt',
            ],
          },
        ),
      ),
    );
  }
}

class AddCompanySheet extends ConsumerStatefulWidget {
  const AddCompanySheet({super.key});

  @override
  ConsumerState<AddCompanySheet> createState() => AddCompanySheetState();
}

class AddCompanySheetState extends ConsumerState<AddCompanySheet> {
  final _nameController = TextEditingController();
  final _domainController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'New Company',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Company Name'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _domainController,
                decoration: const InputDecoration(
                  labelText: 'Domain or Website',
                  hintText: 'e.g. example.com',
                ),
                keyboardType: TextInputType.url,
                enabled: !_isLoading,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() {
                          _errorMessage = null;
                        });
                        if (_formKey.currentState!.validate()) {
                          setState(() {
                            _isLoading = true;
                          });

                          final navigator = Navigator.of(context);

                          try {
                            await ref
                                .read(companiesProvider.notifier)
                                .addCompany(
                                  name: _nameController.text.trim(),
                                  domainName: _domainController.text.trim().isNotEmpty
                                      ? _domainController.text.trim()
                                      : null,
                                );

                            if (!context.mounted) return;
                            navigator.pop();
                            SnackbarHelper.showSuccess(
                              context,
                              'Company created successfully',
                            );
                          } catch (e) {
                            if (mounted) {
                              String errorMsg = e.toString();
                              if (errorMsg.contains('Exception:')) {
                                errorMsg = errorMsg
                                    .replaceAll('Exception:', '')
                                    .trim();
                              }

                              setState(() {
                                _isLoading = false;
                                _errorMessage = errorMsg;
                              });
                            }
                          }
                        }
                      },
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Company'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class EditCompanySheet extends ConsumerStatefulWidget {
  final Company company;

  const EditCompanySheet({super.key, required this.company});

  @override
  ConsumerState<EditCompanySheet> createState() => EditCompanySheetState();
}

class EditCompanySheetState extends ConsumerState<EditCompanySheet> {
  late TextEditingController _nameController;
  late TextEditingController _domainController;
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.company.name);
    _domainController = TextEditingController(text: widget.company.domainName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit Company',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Company Name'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _domainController,
                decoration: const InputDecoration(
                  labelText: 'Domain or Website',
                  hintText: 'e.g. example.com',
                ),
                keyboardType: TextInputType.url,
                enabled: !_isLoading,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() {
                          _errorMessage = null;
                        });
                        if (_formKey.currentState!.validate()) {
                          setState(() {
                            _isLoading = true;
                          });

                          final navigator = Navigator.of(context);

                          try {
                            await ref
                                .read(companiesProvider.notifier)
                                .updateCompany(
                                  widget.company.id,
                                  name: _nameController.text.trim(),
                                  domainName: _domainController.text.trim(),
                                );

                            if (mounted) {
                              navigator.pop();
                              SnackbarHelper.showSuccess(
                                context,
                                'Company updated successfully',
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              String errorMsg = e.toString();
                              if (errorMsg.contains('Exception:')) {
                                errorMsg = errorMsg
                                    .replaceAll('Exception:', '')
                                    .trim();
                              }

                              setState(() {
                                _isLoading = false;
                                _errorMessage = errorMsg;
                              });
                            }
                          }
                        }
                      },
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Changes'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

