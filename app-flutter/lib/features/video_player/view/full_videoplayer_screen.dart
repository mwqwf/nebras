import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/features/video_player/provider/video_player_provider.dart';
import 'package:nebras_mobile_app/features/video_player/view/widgets/control_overlay_widget.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

/// Fullscreen Video Player Page
///
/// ARCHITECTURE RULES:
/// ✅ Receives same provider instance via ChangeNotifierProvider.value
/// ✅ Does NOT create a new provider
/// ✅ Maintains state sync with normal screen
/// ✅ Locks orientation to landscape
/// ✅ Restores portrait on exit
class FullScreenVideopage extends StatefulWidget {
  const FullScreenVideopage({super.key});

  @override
  State<FullScreenVideopage> createState() => _FullScreenVideopageState();
}

class _FullScreenVideopageState extends State<FullScreenVideopage> {
  @override
  void initState() {
    super.initState();
    // Lock to landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore portrait
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerProvider>(
      builder: (context, provider, _) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            await provider.exitFullscreen(context);
          },
          child: Scaffold(
            backgroundColor: ColorsManager.blackcolor,
            body: Stack(
              children: [
                // Video layer
                Center(
                  child: provider.controller != null
                      ? AspectRatio(
                          aspectRatio: provider.controller!.value.aspectRatio,
                          child: VideoPlayer(provider.controller!),
                        )
                      : const SizedBox.shrink(),
                ),
                // Controls overlay
                const Positioned.fill(child: ControlOverlayWidget()),
              ],
            ),
          ),
        );
      },
    );
  }
}
