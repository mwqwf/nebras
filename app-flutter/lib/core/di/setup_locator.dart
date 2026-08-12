import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:nebras_mobile_app/features/audio_player/domain/repos/audio_repo_implem.dart';
import 'package:nebras_mobile_app/features/notifications/domain/repos/firebase_token_repo.dart';
import 'package:nebras_mobile_app/features/notifications/data/firebase_token_repo_impl.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/ensuer_saved_usecase.dart';
import 'package:nebras_mobile_app/features/content/cache/content_metadata_cache.dart';
import 'package:nebras_mobile_app/features/video_player/data/datasources/video_repo_implem.dart';
import 'package:nebras_mobile_app/features/video_player/data/datasources/video_player_datasource.dart';
import 'package:nebras_mobile_app/features/video_player/data/datasources/video_playback_progress_datasource.dart';
import 'package:nebras_mobile_app/features/video_player/domain/repos/video_repos.dart';
import 'package:nebras_mobile_app/features/video_player/domain/usecases/initialize_video_usecase.dart';
import 'package:nebras_mobile_app/features/video_player/domain/usecases/get_last_position_usecase.dart'
    as vid_get;
import 'package:nebras_mobile_app/features/video_player/domain/usecases/save_last_position_usecase.dart'
    as vid_save;
import 'package:nebras_mobile_app/features/video_player/provider/video_player_provider.dart';

// ===== SAVED =====
import 'package:nebras_mobile_app/features/saved/data/saved_local_datasource.dart';
import 'package:nebras_mobile_app/features/saved/domain/repo/saved_repository.dart';
import 'package:nebras_mobile_app/features/saved/domain/repo/saved_repository_impl.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/toggle_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/get_saved_items_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/is_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/remove_saved_usecase.dart';

// ===== SEARCH =====
import 'package:nebras_mobile_app/features/search/data/search_datasource.dart';
import 'package:nebras_mobile_app/features/search/domain/repo/search_repository.dart';
import 'package:nebras_mobile_app/features/search/domain/repo/search_repository_impl.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/search_content_usecase.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_sections_usecase.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_section_content_usecase.dart';
import 'package:nebras_mobile_app/core/network/dio_client.dart';

// ===== HOME =====
import 'package:nebras_mobile_app/features/home/data/home_datasource.dart';
import 'package:nebras_mobile_app/features/home/domain/home_repository.dart';
import 'package:nebras_mobile_app/features/home/domain/home_repository_impl.dart';
import 'package:nebras_mobile_app/features/home/domain/get_home_data_usecase.dart';

// ===== DOWNLOAD =====
import 'package:nebras_mobile_app/features/download/data/download_datasource.dart';
import 'package:nebras_mobile_app/features/download/data/download_item_model.dart';
import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';
import 'package:nebras_mobile_app/features/download/domain/download_repository_impl.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/start_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/pause_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/resume_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/cancel_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/delete_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/get_download_status_usecase.dart';
import 'package:hive/hive.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ===== READER =====
import 'package:nebras_mobile_app/features/reader/data/datasources/book_local_datasource.dart';
import 'package:nebras_mobile_app/features/reader/data/datasources/book_remote_datasource.dart';
import 'package:nebras_mobile_app/features/reader/data/datasources/book_progress_datasource.dart';
import 'package:nebras_mobile_app/features/reader/data/datasources/book_reading_progress_datasource.dart';
import 'package:nebras_mobile_app/features/reader/domain/repos/book_repo_implem.dart';
import 'package:nebras_mobile_app/features/reader/domain/repos/book_repos.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/download_book_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/check_book_download_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/open_book_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/cancel_download_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/get_stored_progress_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/get_last_page_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/save_last_page_usecase.dart';
import 'package:nebras_mobile_app/features/reader/provider/download_provider.dart';
import 'package:nebras_mobile_app/features/reader/provider/reader_provider.dart';

// ===== NOTIFICATIONS =====
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nebras_mobile_app/features/notifications/data/firebase_notification_datasource.dart';
import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo.dart';
import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo_impl.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/get_notification_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/mark_notification_read_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/mark_all_notifications_read_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/delete_notification_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/get_unread_count_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/model/notification_model.dart';

// ===== AUDIO =====
import 'package:nebras_mobile_app/features/audio_player/data/datasources/audio_player_datasource.dart';
import 'package:nebras_mobile_app/features/audio_player/data/datasources/audio_playback_progress_datasource.dart';
import 'package:nebras_mobile_app/features/audio_player/domain/repos/audio_repos.dart';
import 'package:nebras_mobile_app/features/audio_player/domain/usecases/initialize_audio_usecase.dart';
import 'package:nebras_mobile_app/features/audio_player/domain/usecases/get_last_position_usecase.dart';
import 'package:nebras_mobile_app/features/audio_player/domain/usecases/save_last_position_usecase.dart';
import 'package:nebras_mobile_app/features/audio_player/provider/audio_player_provider.dart';
import 'package:nebras_mobile_app/core/firebase/firestore_sync_config.dart';

final locator = GetIt.instance;

Future<void> setupLocator() async {
  // ================= CORE =================

  locator.registerLazySingleton<Dio>(() => Dio());

  final prefs = await SharedPreferences.getInstance();
  locator.registerLazySingleton<SharedPreferences>(() => prefs);

  locator.registerLazySingleton<FirebaseFirestore>(
    () => FirestoreSyncConfig.instance,
  );
  locator.registerLazySingleton<ContentMetadataCache>(
    // كاش الميتادات مركزي؛ أي مصدر بيانات يمرّ عليه محتوى يحدّثه دون أن
    // يغيّر شكل النماذج أو شاشات العرض.
    () => ContentMetadataCache(
      Hive.box<ContentMetadataCacheEntry>('content_metadata_cache'),
    ),
  );

  // ================= NOTIFICATIONS =================

  locator.registerLazySingleton<FirebaseNotificationDatasource>(
    () => FirebaseNotificationDatasource(
      FirebaseMessaging.instance,
      FlutterLocalNotificationsPlugin(),
    ),
  );

  locator.registerLazySingleton<NotificationRepo>(
    () => NotificationRepoImpl(
      locator(),
      Hive.box<NotificationModel>('notifications'),
    ),
  );
  locator.registerLazySingleton<FirebaseTokenRepo>(
    () => FirebaseTokenRepoImpl(),
  );
  locator.registerLazySingleton<GetNotificationsUseCase>(
    () => GetNotificationsUseCase(locator()),
  );
  locator.registerLazySingleton<MarkNotificationReadUseCase>(
    () => MarkNotificationReadUseCase(locator()),
  );
  locator.registerLazySingleton<MarkAllNotificationsReadUseCase>(
    () => MarkAllNotificationsReadUseCase(locator()),
  );
  locator.registerLazySingleton<DeleteNotificationUseCase>(
    () => DeleteNotificationUseCase(locator()),
  );
  locator.registerLazySingleton<GetUnreadCountUseCase>(
    () => GetUnreadCountUseCase(locator()),
  );

  // ================= READER DATASOURCES =================

  locator.registerLazySingleton<BookRemoteDataSource>(
    () => BookRemoteDataSource(locator()),
  );

  locator.registerLazySingleton<BookLocalDatasource>(
    () => BookLocalDatasource(),
  );

  locator.registerLazySingleton<BookProgressDatasource>(
    () => BookProgressDatasource(locator()),
  );

  locator.registerLazySingleton<BookReadingProgressDatasource>(
    () => BookReadingProgressDatasource(locator()),
  );

  // ================= READER REPO =================

  locator.registerLazySingleton<BookRepos>(
    () => BookRepoImplem(locator(), locator(), locator(), locator()),
  );

  // ================= READER USE CASES =================

  locator.registerLazySingleton(() => DownloadBookUsecase(locator()));
  locator.registerLazySingleton(() => CheckBookDownloadedUsecase(locator()));
  locator.registerLazySingleton(() => OpenBookUsecase(locator()));
  locator.registerLazySingleton(() => CancelDownloadUsecase(locator()));
  locator.registerLazySingleton(() => GetStoredProgressUsecase(locator()));
  locator.registerLazySingleton(() => GetLastPageUsecase(locator()));
  locator.registerLazySingleton(() => SaveLastPageUsecase(locator()));

  // ================= PROVIDERS =================

  locator.registerFactory(
    () =>
        DownloadProvider(locator(), locator(), locator(), locator(), locator()),
  );

  locator.registerFactory(() => ReaderProvider(locator(), locator()));

  //================= AUDIO DATASOURCES =================
  locator.registerLazySingleton<AudioPlayerDatasource>(
    () => AudioPlayerDatasource(),
  );

  locator.registerLazySingleton<AudioPlaybackProgressDatasource>(
    () => AudioPlaybackProgressDatasource(locator()),
  );

  locator.registerLazySingleton<AudioRepos>(
    () => AudioRepoImplem(locator(), locator()),
  );

  locator.registerLazySingleton(() => InitializeAudioUsecase(locator()));

  locator.registerLazySingleton(() => GetLastPositionUsecase(locator()));

  locator.registerLazySingleton(() => SaveLastPositionUsecase(locator()));

  locator.registerFactory(
    () => AudioPlayerProvider(locator(), locator(), locator(), locator()),
  );

  // ================= VIDEO =================

  // DataSources
  locator.registerLazySingleton(() => VideoPlayerDatasource());
  locator.registerLazySingleton(() => VideoPlaybackProgressDatasource());

  // Repository
  locator.registerFactory<VideoRepos>(
    () => VideoRepoImplem(
      locator<VideoPlayerDatasource>(),
      locator<VideoPlaybackProgressDatasource>(),
    ),
  );

  // UseCases
  locator.registerFactory(() => InitializeVideoUsecase(locator<VideoRepos>()));

  locator.registerFactory<vid_get.GetLastPositionUsecase>(
    () => vid_get.GetLastPositionUsecase(locator<VideoRepos>()),
  );

  locator.registerFactory<vid_save.SaveLastPositionUsecase>(
    () => vid_save.SaveLastPositionUsecase(locator<VideoRepos>()),
  );

  // Provider
  locator.registerFactory(
    () => VideoPlayerProvider(
      locator<VideoRepos>(),
      locator<InitializeVideoUsecase>(),
      locator<vid_get.GetLastPositionUsecase>(),
      locator<vid_save.SaveLastPositionUsecase>(),
    ),
  );

  // ================= SAVED =================

  // DataSource
  locator.registerLazySingleton(() => SavedLocalDatasource());

  // Repository
  locator.registerLazySingleton<SavedRepository>(
    () => SavedRepositoryImpl(locator()),
  );

  // ================= SAVED =================

  // UseCases
  locator.registerLazySingleton<EnsureSavedUseCase>(
    () => EnsureSavedUseCase(locator()),
  );

  locator.registerLazySingleton(() => ToggleSavedUseCase(locator()));
  locator.registerLazySingleton(() => GetSavedItemsUseCase(locator()));
  locator.registerLazySingleton(() => IsSavedUseCase(locator()));
  locator.registerLazySingleton(() => RemoveSavedUseCase(locator()));

  // ================= SEARCH =================

  // DataSource
  locator.registerLazySingleton(
    () => SearchDatasource(
      locator<FirebaseFirestore>(),
      metadataCache: locator<ContentMetadataCache>(),
    ),
  );

  // Repository
  locator.registerLazySingleton<SearchRepository>(
    () => SearchRepositoryImpl(locator()),
  );

  // UseCases
  locator.registerLazySingleton(() => SearchContentUseCase(locator()));
  locator.registerLazySingleton(() => GetSectionsUseCase(locator()));
  locator.registerLazySingleton(() => GetSectionContentUseCase(locator()));

  // ================= HOME =================

  // DataSource
  locator.registerLazySingleton(
    () => HomeDatasource(
      locator<FirebaseFirestore>(),
      metadataCache: locator<ContentMetadataCache>(),
    ),
  );

  // Repository
  locator.registerLazySingleton<HomeRepository>(
    () => HomeRepositoryImpl(locator()),
  );

  // UseCase
  locator.registerLazySingleton(() => GetHomeDataUseCase(locator()));

  // ================= DOWNLOAD =================

  // DataSource
  locator.registerLazySingleton(
    () => DownloadDatasource(DioClient.createDownloadClient()),
  );

  // Repository
  locator.registerLazySingleton<DownloadRepository>(
    () => DownloadRepositoryImpl(
      locator(),
      Hive.box<DownloadItemModel>('downloads'),
    ),
  );

  // UseCases
  locator.registerLazySingleton(() => StartDownloadUseCase(locator()));
  locator.registerLazySingleton(() => PauseDownloadUseCase(locator()));
  locator.registerLazySingleton(() => ResumeDownloadUseCase(locator()));
  locator.registerLazySingleton(() => CancelDownloadUseCase(locator()));
  locator.registerLazySingleton(() => DeleteDownloadUseCase(locator()));
  locator.registerLazySingleton(() => GetDownloadStatusUseCase(locator()));
}
