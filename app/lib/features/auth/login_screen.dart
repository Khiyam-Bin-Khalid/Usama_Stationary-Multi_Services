import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../data/remote/api_client.dart';

/// Spec §1: the desktop/mobile POS login presents a role selector (Super
/// Admin / Admin / Staff) before credentials. The chosen role is sent to the
/// server, which rejects a mismatch — it is a UX convenience, not access
/// control. Customers sign in through the web store flow instead.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  // Desktop/mobile builds are the POS: staff mode by default. The web build
  // is the customer store: customer mode by default, staff mode via a link.
  bool _staffMode = !kIsWeb;
  String _role = UserRole.staff;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authStateProvider.notifier).login(
            _emailController.text.trim(),
            _passwordController.text,
            role: _staffMode ? _role : UserRole.customer,
          );
      final state = ref.read(authStateProvider);
      if (state.hasError) {
        setState(() => _error = (state.error is ApiException) ? (state.error as ApiException).message : 'Login failed');
      } else if (mounted && state.valueOrNull != null) {
        context.go(UserRole.isPosAdminShell(state.value!.role) ? '/dashboard' : '/shop');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.storefront_outlined, size: 56, color: AppColors.primaryOrange),
                  const SizedBox(height: 12),
                  Text('Usama Book Depot', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  Text(
                    _staffMode ? 'Point of Sale · Staff sign-in' : 'Stationers, General Order Suppliers & Booksellers',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (_staffMode) ...[
                    Text('Sign in as', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final role in const [UserRole.superadmin, UserRole.admin, UserRole.staff]) ...[
                          Expanded(
                            child: _RoleTile(
                              role: role,
                              selected: _role == role,
                              onTap: () => setState(() => _role = role),
                            ),
                          ),
                          if (role != UserRole.staff) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your email' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_staffMode ? 'Log in as ${UserRole.label(_role)}' : 'Log in'),
                  ),
                  const SizedBox(height: 12),
                  if (_staffMode)
                    TextButton(
                      onPressed: () => setState(() => _staffMode = false),
                      child: const Text('Customer? Sign in to the online store'),
                    )
                  else ...[
                    TextButton(
                      onPressed: () => context.go('/register'),
                      child: const Text('New customer? Create an account'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _staffMode = true),
                      child: const Text('Staff / admin sign-in'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final String role;
  final bool selected;
  final VoidCallback onTap;
  const _RoleTile({required this.role, required this.selected, required this.onTap});

  IconData get _icon {
    switch (role) {
      case UserRole.superadmin:
        return Icons.shield_outlined;
      case UserRole.admin:
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.badge_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.tint(AppColors.primaryOrange) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primaryOrange : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(_icon, color: selected ? AppColors.primaryOrange : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              UserRole.label(role),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primaryOrange : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
