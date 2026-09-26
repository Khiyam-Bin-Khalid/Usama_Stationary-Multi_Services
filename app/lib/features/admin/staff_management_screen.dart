import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/user.dart';
import '../../data/remote/api_client.dart';

final _staffListProvider = FutureProvider.autoDispose<List<AppUser>>((ref) => ref.watch(userApiProvider).list());

class StaffManagementScreen extends ConsumerWidget {
  const StaffManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRole = ref.watch(authStateProvider).valueOrNull?.role ?? UserRole.staff;
    final canCreateAdmin = currentRole == UserRole.superadmin;
    final usersAsync = ref.watch(_staffListProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref, canCreateAdmin),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New account'),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (users) => ListView.separated(
          itemCount: users.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final u = users[i];
            return ListTile(
              title: Text(u.name),
              subtitle: Text('${u.email} · ${u.role.toUpperCase()}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusBadge(label: u.isActive ? 'Active' : 'Disabled', tone: u.isActive ? StatusTone.success : StatusTone.neutral),
                  Switch(
                    value: u.isActive,
                    onChanged: (v) async {
                      await ref.read(userApiProvider).update(u.id, {'isActive': v});
                      ref.invalidate(_staffListProvider);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref, bool canCreateAdmin) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String role = UserRole.staff;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New staff/admin account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
              TextField(controller: passwordController, decoration: const InputDecoration(labelText: 'Temporary password')),
              if (canCreateAdmin)
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: UserRole.staff, child: Text('Staff')),
                    DropdownMenuItem(value: UserRole.admin, child: Text('Admin')),
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
                        role: canCreateAdmin ? role : UserRole.staff,
                      );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  ref.invalidate(_staffListProvider);
                } catch (e) {
                  final message = e is ApiException ? e.message : e.toString();
                  if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(message)));
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
