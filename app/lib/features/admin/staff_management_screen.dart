import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/user.dart';

final _staffListProvider = FutureProvider.autoDispose<List<AppUser>>((ref) => ref.watch(userApiProvider).list());

/// Spec §2 / §3.1: only the Super Admin registers, deletes and re-assigns
/// Admin and Staff accounts. The route itself is guarded in the router.
class StaffManagementScreen extends ConsumerWidget {
  const StaffManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(_staffListProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New account'),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (users) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: users.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, i) {
            final u = users[i];
            final isOwner = u.role == UserRole.superadmin;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.tint(isOwner ? AppColors.primaryOrange : AppColors.textSecondary),
                child: Icon(
                  isOwner ? Icons.shield_outlined : (u.role == UserRole.admin ? Icons.admin_panel_settings_outlined : Icons.badge_outlined),
                  color: isOwner ? AppColors.primaryOrange : AppColors.textSecondary,
                ),
              ),
              title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(u.email),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusBadge(label: UserRole.label(u.role), tone: isOwner ? StatusTone.warning : StatusTone.info),
                  const SizedBox(width: 6),
                  StatusBadge(label: u.isActive ? 'Active' : 'Disabled', tone: u.isActive ? StatusTone.success : StatusTone.neutral),
                  if (!isOwner)
                    PopupMenuButton<String>(
                      onSelected: (choice) => _handle(context, ref, u, choice),
                      itemBuilder: (_) => [
                        if (u.role == UserRole.staff) const PopupMenuItem(value: 'admin', child: Text('Change role → Admin')),
                        if (u.role == UserRole.admin) const PopupMenuItem(value: 'staff', child: Text('Change role → Staff')),
                        PopupMenuItem(value: 'toggle', child: Text(u.isActive ? 'Deactivate' : 'Activate')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete account', style: TextStyle(color: AppColors.accentRed))),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, AppUser u, String choice) async {
    try {
      switch (choice) {
        case 'admin':
        case 'staff':
          await ref.read(userApiProvider).changeRole(u.id, choice);
          break;
        case 'toggle':
          await ref.read(userApiProvider).update(u.id, {'isActive': !u.isActive});
          break;
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Delete ${u.name}?'),
              content: const Text('The account can no longer sign in. Its past sales and audit history are kept.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accentRed),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await ref.read(userApiProvider).delete(u.id);
          break;
      }
      ref.invalidate(_staffListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account updated'), backgroundColor: AppColors.success));
      }
    } catch (e) {
      final message = e.toString();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.accentRed));
    }
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String role = UserRole.staff;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New staff / admin account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary password')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: UserRole.staff, child: Text('Staff — counter sales, read-only stock')),
                  DropdownMenuItem(value: UserRole.admin, child: Text('Admin — inventory, orders, promotions, reports')),
                ],
                onChanged: (v) => setDialogState(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await ref.read(authApiProvider).createStaffAccount(
                        name: nameController.text,
                        email: emailController.text,
                        password: passwordController.text,
                        role: role,
                      );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  ref.invalidate(_staffListProvider);
                } catch (e) {
                  final message = e.toString();
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.accentRed));
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
