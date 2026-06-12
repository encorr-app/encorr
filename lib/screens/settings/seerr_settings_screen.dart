import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_text_field.dart';
import '../../providers/seerr_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/settings_section.dart';

/// Seerr (Overseerr/Jellyseerr successor) integration settings: server URL,
/// one-tap "Sign in with Plex" using the already-stored Plex account token,
/// signed-in status, and sign-out.
class SeerrSettingsScreen extends StatefulWidget {
  const SeerrSettingsScreen({super.key});

  @override
  State<SeerrSettingsScreen> createState() => _SeerrSettingsScreenState();
}

class _SeerrSettingsScreenState extends State<SeerrSettingsScreen> {
  late final TextEditingController _urlController;
  final _signInFocusNode = FocusNode(debugLabel: 'SeerrSignIn');

  @override
  void initState() {
    super.initState();
    final provider = context.read<SeerrProvider>();
    _urlController = TextEditingController(text: provider.serverUrl ?? '');
  }

  @override
  void dispose() {
    _signInFocusNode.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final provider = context.read<SeerrProvider>();
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      showErrorSnackBar(context, 'Enter your Seerr server URL first');
      return;
    }
    final ok = await provider.signIn(url);
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Signed in to Seerr as ${provider.displayName ?? 'Plex user'}');
    } else {
      showErrorSnackBar(context, provider.lastError ?? 'Sign-in failed');
    }
  }

  Future<void> _signOut() async {
    final provider = context.read<SeerrProvider>();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out of Seerr',
      message: 'Your session on this device will be removed. The server URL is kept.',
      confirmText: 'Sign out',
      isDestructive: true,
    );
    if (!confirmed) return;
    await provider.signOut();
    if (mounted) showAppSnackBar(context, 'Signed out of Seerr');
  }

  @override
  Widget build(BuildContext context) {
    return FocusedScrollScaffold(
      title: const Text('Seerr'),
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Connect a Seerr (Overseerr) server to discover and request movies and shows. '
                'Sign-in reuses your Plex account — no extra password needed.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SettingsSectionHeader('Server'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FocusableTextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://seerr.example.com',
                  prefixIcon: AppIcon(Symbols.dns_rounded, fill: 1),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onEditingComplete: () => _signInFocusNode.requestFocus(),
              ),
            ),
            Consumer<SeerrProvider>(
              builder: (context, provider, _) => Column(
                crossAxisAlignment: .start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        focusNode: _signInFocusNode,
                        onPressed: provider.isSigningIn ? null : _signIn,
                        icon: provider.isSigningIn
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const AppIcon(Symbols.login_rounded, fill: 1),
                        label: Text(
                          provider.isSigningIn
                              ? 'Signing in…'
                              : (provider.isSignedIn ? 'Re-sign in with Plex' : 'Sign in with Plex'),
                        ),
                      ),
                    ),
                  ),
                  const SettingsSectionHeader('Account'),
                  if (provider.isSignedIn) ...[
                    ListTile(
                      leading: const AppIcon(Symbols.check_circle_rounded, fill: 1),
                      title: Text('Signed in as ${provider.displayName ?? 'Plex user'}'),
                      subtitle: Text(provider.serverUrl ?? ''),
                    ),
                    ListTile(
                      leading: const AppIcon(Symbols.logout_rounded, fill: 1),
                      title: const Text('Sign out'),
                      subtitle: const Text('Remove the Seerr session from this device'),
                      onTap: _signOut,
                    ),
                  ] else
                    const ListTile(
                      leading: AppIcon(Symbols.link_off_rounded, fill: 1),
                      title: Text('Not signed in'),
                      subtitle: Text('Enter your server URL and sign in with your Plex account'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ],
    );
  }
}
