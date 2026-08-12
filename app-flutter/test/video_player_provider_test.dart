import 'package:flutter_test/flutter_test.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/video_player/domain/repos/video_repos.dart';
import 'package:nebras_mobile_app/features/video_player/domain/usecases/get_last_position_usecase.dart';
import 'package:nebras_mobile_app/features/video_player/domain/usecases/initialize_video_usecase.dart';
import 'package:nebras_mobile_app/features/video_player/domain/usecases/save_last_position_usecase.dart';
import 'package:nebras_mobile_app/features/video_player/provider/video_player_provider.dart';
import 'package:video_player/video_player.dart';

void main() {
  test(
    'video provider stores speed, quality, mini-player, and playlist state',
    () async {
      final repo = _FakeVideoRepos();
      final provider = VideoPlayerProvider(
        repo,
        InitializeVideoUsecase(repo),
        GetLastPositionUsecase(repo),
        SaveLastPositionUsecase(repo),
      );

      final first = _content('one');
      final second = _content('two');
      provider.setPlaylist(playlist: [first, second], currentIndex: 0);
      await provider.setPlayBackSpeed(1.5);
      provider.setQualityLabel('720p');
      provider.toggleInAppMiniPlayer();

      expect(provider.currentVideo?.id, 'one');
      expect(provider.nextSuggestion?.id, 'two');
      expect(provider.playBackSpeed, 1.5);
      expect(provider.qualityLabel, '720p');
      expect(provider.isInAppMiniPlayer, isTrue);
      expect(repo.lastSpeed, 1.5);
    },
  );

  test(
    'video provider can request similar content for smart autoplay',
    () async {
      final repo = _FakeVideoRepos();
      final provider = VideoPlayerProvider(
        repo,
        InitializeVideoUsecase(repo),
        GetLastPositionUsecase(repo),
        SaveLastPositionUsecase(repo),
      );

      provider.setContentContext(ContentContext.home);
      provider.setPlaylist(playlist: [_content('one')], currentIndex: 0);
      provider.onSimilarContentNeeded =
          ({required reference, required limit}) async {
            return [_content('two')];
          };

      await provider.playSimilarContent(limit: 1);

      expect(provider.playlist.map((c) => c.id), ['one', 'two']);
      expect(provider.currentVideo?.id, 'one');
      expect(provider.showNextSuggestion, isTrue);
      expect(provider.nextSuggestion?.id, 'two');

      await provider.acceptNextSuggestion();

      expect(provider.currentVideo?.id, 'two');
      expect(repo.initializedSources, contains('https://example.com/two.mp4'));
    },
  );

  test('video provider shows countdown for an existing next video', () {
    final repo = _FakeVideoRepos();
    final provider = VideoPlayerProvider(
      repo,
      InitializeVideoUsecase(repo),
      GetLastPositionUsecase(repo),
      SaveLastPositionUsecase(repo),
    );

    provider.setPlaylist(
      playlist: [_content('one'), _content('two')],
      currentIndex: 0,
    );
    provider.startNextSuggestionCountdownForTest(seconds: 3);

    expect(provider.showNextSuggestion, isTrue);
    expect(provider.nextSuggestion?.id, 'two');
    expect(provider.nextSuggestionSeconds, 3);

    provider.cancelNextSuggestion();
    expect(provider.showNextSuggestion, isFalse);
  });

  test('video provider exposes bounded next suggestion overlay state', () {
    final repo = _FakeVideoRepos();
    final provider = VideoPlayerProvider(
      repo,
      InitializeVideoUsecase(repo),
      GetLastPositionUsecase(repo),
      SaveLastPositionUsecase(repo),
    );

    provider.setPlaylist(
      playlist: [_content('one'), _content('two')],
      currentIndex: 0,
    );
    provider.startNextSuggestionCountdownForTest(seconds: 2);

    expect(provider.showNextSuggestion, isTrue);
    expect(provider.nextSuggestion?.title, 'Video two');
    expect(provider.nextSuggestionSeconds, 2);
  });
}

Content _content(String id) {
  return Content(
    id: id,
    title: 'Video $id',
    author: '',
    description: '',
    type: ContentType.video,
    thumbnailUrl: '',
    section: 'section',
    sourceUrl: 'https://example.com/$id.mp4',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    createdBy: '',
  );
}

class _FakeVideoRepos implements VideoRepos {
  final initializedSources = <String>[];
  double? lastSpeed;

  @override
  Future<void> initializeVideo(String source) async {
    initializedSources.add(source);
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSpeed(double speed) async {
    lastSpeed = speed;
  }

  @override
  Stream<Duration> getPositionStream() => const Stream.empty();

  @override
  Stream<Duration?> getDurationStream() => const Stream.empty();

  @override
  Stream<bool> getPlayingStateStream() => const Stream.empty();

  @override
  Stream<List<DurationRange>> getBufferedStream() => const Stream.empty();

  @override
  bool isPlaying() => false;

  @override
  Duration getCurrentPosition() => Duration.zero;

  @override
  Duration? getDuration() => const Duration(minutes: 1);

  @override
  double getAspectRatio() => 16 / 9;

  @override
  bool isInitialized() => true;

  @override
  VideoPlayerController? getController() => null;

  @override
  Future<void> saveLastPosition(
    String videoId,
    Duration position,
    Duration duration,
  ) async {}

  @override
  Future<Duration?> getLastPosition(String videoId) async => null;

  @override
  Future<void> clearProgress(String videoId) async {}

  @override
  Future<void> dispose() async {}
}
