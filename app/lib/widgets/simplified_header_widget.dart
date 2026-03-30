import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../screens/library_screen.dart';
import '../state/app_state.dart';
import 'tutorial_pulse_widget.dart';

class SimplifiedHeaderWidget extends StatelessWidget {
  const SimplifiedHeaderWidget({
    Key? key,
    this.onLogoTap,
  }) : super(key: key);

  static const double _logoIconMinSize = 36;
  static const double _logoIconMaxSize = 64;
  static const double _logoIconBorderWidth = 1.0;

  final VoidCallback? onLogoTap;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 66, 66, 66),
        border: Border(
          bottom: BorderSide(
            color: AppColors.sequencerBorder,
            width: 0.5,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final logoSize = (constraints.maxWidth * 0.18).clamp(
            _logoIconMinSize,
            _logoIconMaxSize,
          );
          final logoRadius = (logoSize * 0.24).clamp(4.0, 8.0);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(logoRadius),
                child: InkWell(
                  onTap: onLogoTap,
                  borderRadius: BorderRadius.circular(logoRadius),
                  child: Container(
                    width: logoSize,
                    height: logoSize,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(logoRadius),
                      image: const DecorationImage(
                        image: AssetImage('icons/white_mane1_cut_gray(1).png'),
                        fit: BoxFit.cover,
                      ),
                      border: Border.all(
                        color: const Color.fromARGB(255, 50, 50, 50),
                        width: _logoIconBorderWidth,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),

              // Spacer
              const Expanded(
                child: SizedBox(),
              ),

              // Right side - Library icon
              TutorialPulseWidget(
                enabled: appState.activeTutorialStep ==
                    TutorialStep.sequencerProjectsLibraryHint,
                borderRadius: BorderRadius.circular(10),
                child: IconButton(
                  key: appState.activeTutorialStep ==
                          TutorialStep.sequencerProjectsLibraryHint
                      ? appState.projectsLibraryFolderTutorialKey
                      : null,
                  onPressed: () {
                    appState.markProjectsLibraryFolderOpenAction();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LibraryScreen(),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.folder_outlined,
                    color: AppColors.sequencerText,
                    size: 28,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                  ),
                  padding: const EdgeInsets.all(8),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
