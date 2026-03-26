import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketcrm/presentation/shared/dialog_helper.dart';

class SwipeActionWrapper extends StatelessWidget {
  final Key itemKey;
  final Widget child;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final String confirmTitle;
  final String confirmMessage;

  const SwipeActionWrapper({
    super.key,
    required this.itemKey,
    required this.child,
    required this.onDelete,
    this.onEdit,
    required this.confirmTitle,
    required this.confirmMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: itemKey,
      direction: onEdit != null ? DismissDirection.horizontal : DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(
          Icons.edit,
          color: Colors.white,
        ),
      ),
      secondaryBackground: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          onEdit?.call();
          return false; // Non rimuoviamo la card dal widget tree per l'edit
        } else {
          return await DialogHelper.showDeleteConfirmDialog(
            context: context,
            title: confirmTitle,
            message: confirmMessage,
          );
        }
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onDelete();
        }
      },
      child: child,
    );
  }
}
