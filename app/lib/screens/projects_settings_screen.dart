import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../utils/app_colors.dart';

class ProjectsSettingsScreen extends StatelessWidget {
  const ProjectsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final showRunTutorial = appState.showRunTutorialButtonOnProjectsSettings;

    return Scaffold(
      backgroundColor: AppColors.sequencerPageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.sequencerSurfaceBase,
        foregroundColor: AppColors.sequencerText,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                onPressed: () => _openPrivacyPolicy(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.sequencerText,
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Privacy Policy'),
              ),
              if (showRunTutorial) ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    context.read<AppState>().requestRunTutorialFromProjects();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sequencerAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Run tutorial'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final rawUrl = dotenv.env['PRIVACY_POLICY_URL']?.trim() ?? '';
    if (rawUrl.isEmpty) {
      _showError(context, 'Privacy policy URL is not configured.');
      return;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      _showError(context, 'Privacy policy URL is invalid.');
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      _showError(context, 'Could not open privacy policy.');
    }
  }

  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
