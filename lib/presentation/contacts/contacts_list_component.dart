import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/utils/color_utils.dart';
import 'package:pocketcrm/core/utils/demo_utils.dart';
import 'package:pocketcrm/presentation/contacts/edit_contact_sheet.dart';
import 'package:pocketcrm/presentation/shared/dynamic_fields/dynamic_field_renderer.dart';
import 'package:pocketcrm/presentation/shared/dynamic_fields/entity_field_metadata.dart';
import 'package:pocketcrm/presentation/shared/empty_state_widget.dart';
import 'package:pocketcrm/presentation/shared/error_state_widget.dart';
import 'package:pocketcrm/presentation/shared/skeleton_loading.dart';
import 'package:pocketcrm/presentation/shared/snackbar_helper.dart';
import 'package:pocketcrm/presentation/shared/swipe_action_wrapper.dart';

class ContactsListComponent extends ConsumerStatefulWidget {
  const ContactsListComponent({
    super.key,
    required this.scrollController,
  });

  final ScrollController scrollController;

  @override
  ConsumerState<ContactsListComponent> createState() => _ContactsListComponentState();
}

class _ContactsListComponentState extends ConsumerState<ContactsListComponent> {
  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final pos = widget.scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      ref.read(contactsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);

    return contactsAsync.when(
      data: (contacts) {
        if (contacts.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(contactsProvider.future),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: const EmptyStateWidget(
                  icon: Icons.people_outline,
                  title: 'No contacts',
                  message: 'No results match your search.',
                ),
              ),
            ),
          );
        }
        final notifier = ref.read(contactsProvider.notifier);
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(contactsProvider);
            await ref.read(contactsProvider.future);
          },
          child: ListView.separated(
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: contacts.length + 1,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              if (index == contacts.length) {
                if (notifier.hasNextPage) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return const SizedBox.shrink();
              }
              final contact = contacts[index];
              final bgColor = ColorUtils.avatarColor(contact.firstName);
              return SwipeActionWrapper(
                itemKey: ValueKey('contact_${contact.id}'),
                confirmTitle: 'Delete contact',
                confirmMessage:
                    'Are you sure you want to delete ${contact.firstName} ${contact.lastName}?\nThis action cannot be undone.',
                onDelete: () async {
                  if (!await DemoUtils.checkDemoAction(context, ref)) return;
                  try {
                    await ref.read(contactsProvider.notifier).deleteContact(contact.id);
                    if (context.mounted) {
                      SnackbarHelper.showSuccess(context, 'Contact deleted');
                    }
                  } catch (_) {
                    if (context.mounted) {
                      SnackbarHelper.showError(context, 'Error during deletion');
                    }
                  }
                },
                onEdit: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => EditContactSheet(contact: contact),
                  );
                },
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: bgColor.withOpacity(0.2),
                      backgroundImage: (contact.avatarUrl != null && contact.avatarUrl!.isNotEmpty)
                          ? CachedNetworkImageProvider(contact.avatarUrl!)
                          : null,
                      child: contact.avatarUrl == null
                          ? Text(
                              contact.firstName.isNotEmpty ? contact.firstName[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: bgColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      '${contact.firstName} ${contact.lastName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    subtitle: DynamicFieldRenderer(
                      entity: contact,
                      descriptors: EntityFieldMetadata.contactList,
                      maxLines: 1,
                      textStyle: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                    ),
                    onTap: () => context.push('/contacts/${contact.id}'),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const ListSkeleton(),
      error: (err, _) => ErrorStateWidget(
        title: 'Loading error',
        message: err.toString().replaceAll('Exception: ', ''),
        onRetry: () => ref.invalidate(contactsProvider),
      ),
    );
  }
}
