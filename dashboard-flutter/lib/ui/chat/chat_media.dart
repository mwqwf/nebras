import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';

/// مشغّل صوت مشترك — مشغّل واحد فقط يعمل في أيّ لحظة (مثل واتساب).
class SharedAudioPlayer {
  SharedAudioPlayer._();
  static final SharedAudioPlayer instance = SharedAudioPlayer._();

  final AudioPlayer player = AudioPlayer();

  /// رابط المقطع النشط حاليّاً — تراقبه الفقاعات لتعرف أيّها يعمل.
  final ValueNotifier<String?> activeUrl = ValueNotifier<String?>(null);

  Future<void> play(String url) async {
    if (activeUrl.value == url) {
      await player.resume();
      return;
    }
    activeUrl.value = url;
    await player.stop();
    await player.play(UrlSource(url));
  }

  Future<void> pause() => player.pause();

  Future<void> stop() async {
    activeUrl.value = null;
    await player.stop();
  }
}

/// فقاعة تشغيل صوت (مقطع صوتي أو رسالة صوتيّة) — زرّ تشغيل + شريط تقدّم.
class AudioBubblePlayer extends StatefulWidget {
  const AudioBubblePlayer({
    super.key,
    required this.url,
    this.durationMs,
    this.isVoice = false,
  });

  final String url;
  final int? durationMs;
  final bool isVoice;

  @override
  State<AudioBubblePlayer> createState() => _AudioBubblePlayerState();
}

class _AudioBubblePlayerState extends State<AudioBubblePlayer> {
  final _shared = SharedAudioPlayer.instance;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;

  bool get _isActive => _shared.activeUrl.value == widget.url;

  @override
  void initState() {
    super.initState();
    _dur = Duration(milliseconds: widget.durationMs ?? 0);
    _shared.activeUrl.addListener(_onSharedChange);
    _shared.player.onPositionChanged.listen((d) {
      if (mounted && _isActive) setState(() => _pos = d);
    });
    _shared.player.onDurationChanged.listen((d) {
      if (mounted && _isActive && d > Duration.zero) setState(() => _dur = d);
    });
    _shared.player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = _isActive && s == PlayerState.playing);
    });
    _shared.player.onPlayerComplete.listen((_) {
      if (mounted && _isActive) {
        setState(() {
          _playing = false;
          _pos = Duration.zero;
        });
      }
    });
  }

  void _onSharedChange() {
    if (mounted) setState(() => _playing = false);
  }

  @override
  void dispose() {
    _shared.activeUrl.removeListener(_onSharedChange);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final active = _isActive;
    final pos = active ? _pos : Duration.zero;
    final total = _dur > Duration.zero ? _dur : const Duration(seconds: 1);
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () async {
              if (_playing) {
                await _shared.pause();
              } else {
                await _shared.play(widget.url);
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: NebrasColors.emeraldDark,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: NebrasColors.emerald,
                    inactiveTrackColor: NebrasColors.border,
                    thumbColor: NebrasColors.emerald,
                  ),
                  child: Slider(
                    value: pos.inMilliseconds
                        .clamp(0, total.inMilliseconds)
                        .toDouble(),
                    max: total.inMilliseconds.toDouble(),
                    onChanged: active
                        ? (v) => _shared.player
                            .seek(Duration(milliseconds: v.toInt()))
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _dur > Duration.zero
                        ? '${_fmt(pos)} / ${_fmt(_dur)}'
                        : _fmt(pos),
                    style: const TextStyle(
                        fontSize: 10.5, color: NebrasColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            widget.isVoice ? Icons.mic : Icons.music_note,
            size: 18,
            color: NebrasColors.textMuted,
          ),
        ],
      ),
    );
  }
}

/// عارض صورة بملء الشاشة مع تكبير/تصغير.
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.url, required this.name});

  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(name, style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: CachedNetworkImage(
            imageUrl: url,
            placeholder: (_, __) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white54, size: 60),
          ),
        ),
      ),
    );
  }
}

/// صفحة تشغيل فيديو بملء الشاشة (شبكة — يبثّ مباشرة من Storage).
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.url, required this.name});

  final String url;
  final String name;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // إيقاف أيّ صوت جارٍ قبل تشغيل الفيديو.
    SharedAudioPlayer.instance.stop();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      }).catchError((e) {
        if (mounted) setState(() => _error = 'تعذّر تشغيل الفيديو: $e');
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.name, style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: NebrasColors.rose)),
              )
            : !_ready
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio == 0
                              ? 16 / 9
                              : _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: NebrasColors.emerald,
                          bufferedColor: NebrasColors.surfaceAlt,
                          backgroundColor: NebrasColors.border,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              iconSize: 34,
                              color: Colors.white,
                              icon: const Icon(Icons.replay_10),
                              onPressed: () async {
                                final p = await _controller.position ??
                                    Duration.zero;
                                _controller.seekTo(
                                    p - const Duration(seconds: 10));
                              },
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              iconSize: 48,
                              color: Colors.white,
                              icon: Icon(_controller.value.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled),
                              onPressed: () {
                                setState(() {
                                  _controller.value.isPlaying
                                      ? _controller.pause()
                                      : _controller.play();
                                });
                              },
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              iconSize: 34,
                              color: Colors.white,
                              icon: const Icon(Icons.forward_10),
                              onPressed: () async {
                                final p = await _controller.position ??
                                    Duration.zero;
                                _controller.seekTo(
                                    p + const Duration(seconds: 10));
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
