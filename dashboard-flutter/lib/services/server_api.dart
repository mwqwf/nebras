import '../core/api_client.dart';

/// أغلفة نقاط الـ API الخادمية للوحة (كلّها محميّة بـ Bearer Firebase ID token).
/// تطابق `internetArchive.js` / `noorLibrary.js` / `hindawiLibrary.js` /
/// `crawl4ai.js` / `supervisors.js` / `admin.js`.
class ServerApi {
  ServerApi._();
  static final ServerApi instance = ServerApi._();
  final _api = ApiClient.instance;

  // ─── محرّك عام (Internet Archive / Noor / Hindawi) ───────

  /// مسار الأساس لكل محرّك.
  static String engineBase(EngineKind kind) => switch (kind) {
    EngineKind.internetArchive => '/api/admin/internet-archive/engine',
    EngineKind.noor => '/api/admin/noor-library/engine',
    EngineKind.hindawi => '/api/admin/hindawi-library/engine',
  };

  Future<dynamic> engineStatus(EngineKind kind, {int logLimit = 30}) {
    final base = engineBase(kind);
    final path = kind == EngineKind.internetArchive
        ? '$base/status'
        : '$base/status?limit=$logLimit';
    return _api.authedJson(path);
  }

  Future<dynamic> engineStart(EngineKind kind) =>
      _api.authedJson('${engineBase(kind)}/start', method: 'POST', body: {});

  Future<dynamic> engineStop(EngineKind kind) =>
      _api.authedJson('${engineBase(kind)}/stop', method: 'POST', body: {});

  Future<dynamic> engineTick(EngineKind kind) =>
      _api.authedJson('${engineBase(kind)}/tick', method: 'POST', body: {});

  /// إعادة الضبط. IA يستعمل {type}، Noor/Hindawi يستعملان {mode}.
  Future<dynamic> engineReset(EngineKind kind, {String type = 'cursor'}) {
    final base = engineBase(kind);
    if (kind == EngineKind.internetArchive) {
      return _api.authedJson(
        '$base/reset',
        method: 'POST',
        body: {'type': type},
      );
    }
    return _api.authedJson('$base/reset', method: 'POST', body: {'mode': type});
  }

  // ─── Internet Archive (خاص) ─────────────────────────────

  Future<dynamic> iaBootstrap() => _api.authedJson(
    '/api/admin/internet-archive/engine/bootstrap',
    method: 'POST',
    body: {},
  );

  Future<dynamic> iaDiagnose() => _api.authedJson(
    '/api/admin/internet-archive/engine/diagnose',
    method: 'POST',
    body: {},
  );

  Future<dynamic> iaSectionsTree() =>
      _api.authedJson('/api/admin/internet-archive/sections');

  Future<dynamic> iaSearch(Map<String, dynamic> args) => _api.authedJson(
    '/api/admin/internet-archive/search',
    method: 'POST',
    body: args,
  );

  Future<dynamic> iaPreview(Map<String, dynamic> args) => _api.authedJson(
    '/api/admin/internet-archive/preview',
    method: 'POST',
    body: args,
  );

  Future<dynamic> iaImport(Map<String, dynamic> args) => _api.authedJson(
    '/api/admin/internet-archive/import',
    method: 'POST',
    body: args,
  );

  // ─── Noor / Hindawi diagnose ────────────────────────────

  Future<dynamic> librariesDiagnose(String source) =>
      _api.authedJson('/api/admin/libraries/diagnose?source=$source');

  Future<dynamic> noorSectionsTree() =>
      _api.authedJson('/api/admin/noor-library/sections');

  Future<dynamic> noorPreview(String url) => _api.authedJson(
    '/api/admin/noor-library/preview',
    method: 'POST',
    body: {'url': url},
  );

  Future<dynamic> noorImport(Map<String, dynamic> payload) => _api.authedJson(
    '/api/admin/noor-library/import',
    method: 'POST',
    body: payload,
  );

  Future<dynamic> noorJobs({int limit = 30}) =>
      _api.authedJson('/api/admin/noor-library/jobs?limit=$limit');

  // ─── crawl4ai ───────────────────────────────────────────

  Future<dynamic> crawl4aiStatus() =>
      _api.authedJson('/api/admin/crawl4ai/status');

  Future<dynamic> crawl4aiControl(String action) => _api.authedJson(
    '/api/admin/crawl4ai/control',
    method: 'POST',
    body: {'action': action},
  );

  Future<dynamic> crawl4aiEnqueue(String url) => _api.authedJson(
    '/api/admin/crawl4ai/crawl',
    method: 'POST',
    body: {'url': url},
  );

  Future<dynamic> crawl4aiJobs({int limit = 50}) =>
      _api.authedJson('/api/admin/crawl4ai/jobs?limit=$limit');

  // ─── المشرفون ───────────────────────────────────────────

  Future<dynamic> listSupervisors() =>
      _api.authedJson('/api/admin/supervisors');

  Future<dynamic> setSupervisorBlocked(
    String uid,
    bool isBlocked, {
    String mode = 'temporary',
  }) => _api.authedJson(
    '/api/admin/supervisors/${Uri.encodeComponent(uid)}',
    method: 'PATCH',
    body: {'isBlocked': isBlocked, 'mode': mode},
  );

  Future<dynamic> removeSupervisor(String uid) => _api.authedJson(
    '/api/admin/supervisors/${Uri.encodeComponent(uid)}',
    method: 'DELETE',
  );

  // ─── إحصاءات / تقارير / تدقيق ───────────────────────────

  Future<dynamic> aggregatesOverview() =>
      _api.authedJson('/api/admin/aggregates/overview');

  Future<dynamic> aggregatesBySource() =>
      _api.authedJson('/api/admin/aggregates/by-source');

  Future<dynamic> reports({Map<String, String>? query}) =>
      _api.authedJson('/api/admin/reports', query: query);

  /// إجراء على بلاغ: {action:'dismiss'|'delete', reportId, contentId, contentType?}
  Future<dynamic> reportAction(Map<String, dynamic> body) =>
      _api.authedJson('/api/admin/reports', method: 'POST', body: body);

  /// قنوات ومنشورات «مجتمع نبراس» التي تحتاج إلى إشراف.
  Future<dynamic> communityModeration() =>
      _api.authedJson('/api/admin/community');

  /// تعليق قناة أو فك تعليقها، وحذف منشور مخالف وفق صلاحية المستخدم.
  Future<dynamic> communityAction(Map<String, dynamic> body) =>
      _api.authedJson('/api/admin/community', method: 'POST', body: body);

  Future<dynamic> contentAudit({Map<String, String>? query}) =>
      _api.authedJson('/api/admin/content-audit', query: query);

  /// حذف عنصر مُعلَّم من تدقيق المحتوى.
  Future<dynamic> contentAuditDelete(String contentId, String contentType) =>
      _api.authedJson(
        '/api/admin/content-audit',
        method: 'POST',
        body: {
          'action': 'delete',
          'contentId': contentId,
          'contentType': contentType,
        },
      );

  // ─── إشعارات FCM ────────────────────────────────────────

  Future<dynamic> notify(Map<String, dynamic> body) =>
      _api.authedJson('/api/notify', method: 'POST', body: body);
}

enum EngineKind { internetArchive, noor, hindawi }
