import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../providers/seerr_provider.dart';
import '../../utils/platform_detector.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';

/// Inline Seerr connect UI: server URL + Plex sign-in. Used on the Requests tab
/// when the user has not signed in yet.
class SeerrConnectPrompt extends StatefulWidget {
  const SeerrConnectPrompt({
    super.key,
    this.onNavigateLeft,
    this.onOpenSettings,
    this.autofocus = false,
  });

  final VoidCallback? onNavigateLeft;
  final VoidCallback? onOpenSettings;
  final bool autofocus;

  @override
  State<SeerrConnectPrompt> createState() => _SeerrConnectPromptState();
}

class _SeerrConnectPromptState extends State<SeerrConnectPrompt> {
  late final TextEditingController _urlController;
  final _signInFocusNode = FocusNode(debugLabel: 'SeerrConnectSignIn');

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<SeerrProvider>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(Symbols.playlist_add_rounded, size: 56, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('Requests', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                provider.isConfigured
                    ? 'Sign in to your Seerr server to browse trending titles and request new content.'
                    : 'Connect a Seerr server to browse trending titles and request movies and shows.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FocusableTextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Seerr server URL',
                  hintText: 'https://seerr.example.com',
                  prefixIcon: AppIcon(Symbols.dns_rounded, fill: 1),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onEditingComplete: () => _signInFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              FocusableButton(
                autofocus: widget.autofocus && PlatformDetector.isTV(),
                onPressed: provider.isSigningIn ? null : _signIn,
                onNavigateLeft: widget.onNavigateLeft,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: provider.isSigningIn ? null : _signIn,
                    icon: provider.isSigningIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const AppIcon(Symbols.login_rounded, fill: 1),
                    label: Text(provider.isSigningIn ? 'Signing in…' : 'Sign in with Plex'),
                  ),
                ),
              ),
              if (widget.onOpenSettings != null) ...[
                const SizedBox(height: 12),
                FocusableButton(
                  onPressed: widget.onOpenSettings,
                  onNavigateLeft: widget.onNavigateLeft,
                  child: TextButton(
                    onPressed: widget.onOpenSettings,
                    child: const Text('Seerr account settings'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
