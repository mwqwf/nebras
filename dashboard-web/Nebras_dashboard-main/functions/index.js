/**
 * تنبيهات الإشراف المباشرة.
 *
 * هذا Trigger موثوق لأنه يتفاعل فقط مع وثيقة موجودة بالفعل في Firestore؛
 * أي إن قواعد المحتوى هي التي تتحقق من البلاغ قبل أن يصل إلى FCM. لا يعتمد
 * على عميل التطبيق لإرسال إشعار قابل للإساءة، ويشمل البلاغات من الضيوف.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

initializeApp();

const MODERATOR_REPORTS_TOPIC = 'nebras_moderator_reports';

export const notifyModeratorsOfReport = onDocumentCreated(
  {
    document: 'content_reports/{reportId}',
    database: 'default',
    region: 'europe-west1'
  },
  async (event) => {
    const report = event.data?.data() || {};
    if (String(report.status || 'pending') !== 'pending') return;

    const reportId = String(event.params.reportId || '');
    const contentId = String(report.contentId || '');
    const contentTitle = String(report.contentTitle || '').trim();
    const reason = String(report.reasonCode || 'other');
    const title = 'بلاغ محتوى جديد';
    const body = contentTitle
      ? `${contentTitle} — السبب: ${reason}`
      : `المحتوى: ${contentId || 'غير معروف'} — السبب: ${reason}`;

    await getMessaging().send({
      topic: MODERATOR_REPORTS_TOPIC,
      data: {
        kind: 'content_report',
        title,
        body,
        reportId,
        contentId,
        contentType: String(report.contentType || '')
      },
      android: { priority: 'high' },
      apns: {
        headers: { 'apns-priority': '5', 'apns-push-type': 'background' },
        payload: { aps: { 'content-available': 1 } }
      }
    });
  }
);

/** ينبه متابعي القناة فقط عند نشر منشور مجتمع جديد. */
export const notifyChannelFollowersOfPost = onDocumentCreated(
  {
    document: 'ugc_contents/{postId}',
    database: 'default',
    region: 'europe-west1'
  },
  async (event) => {
    const post = event.data?.data() || {};
    if (String(post.status || 'published') !== 'published') return;
    if (String(post.channelStatus || 'active') !== 'active') return;

    const postId = String(event.params.postId || '');
    const channelId = String(post.channelId || '').trim();
    if (!channelId) return;

    const channelName = String(post.channelName || 'قناة تتابعها').trim();
    const contentTitle = String(post.title || 'منشور جديد').trim();
    await getMessaging().send({
      topic: `nebras_channel_${channelId}`,
      data: {
        kind: 'ugc_channel_post',
        type: 'ugc_channel_post',
        title: `جديد في ${channelName}`,
        body: contentTitle,
        contentId: postId,
        contentType: String(post.content_type || ''),
        channelId
      },
      android: { priority: 'high' },
      apns: {
        headers: { 'apns-priority': '5', 'apns-push-type': 'background' },
        payload: { aps: { 'content-available': 1 } }
      }
    });
  }
);

/** ينبه صاحب القناة بوصول تعليق جديد من دون تضمين نصّه أو بيانات كاتبه. */
export const notifyPublisherOfComment = onDocumentCreated(
  {
    document: 'ugc_contents/{postId}/comments/{commentId}',
    database: 'default',
    region: 'europe-west1'
  },
  async (event) => {
    const comment = event.data?.data() || {};
    const postId = String(event.params.postId || '');
    if (!postId) return;

    const postSnap = await getFirestore('default').collection('ugc_contents').doc(postId).get();
    if (!postSnap.exists) return;
    const post = postSnap.data() || {};
    const channelId = String(post.channelId || '').trim();
    if (!channelId || String(comment.uid || '') === channelId) return;

    await getMessaging().send({
      topic: `nebras_publisher_${channelId}`,
      data: {
        kind: 'ugc_comment',
        type: 'ugc_comment',
        title: 'تعليق جديد على منشورك',
        body: String(post.title || 'افتح نبراس لقراءة التعليق'),
        contentId: postId,
        contentType: String(post.content_type || ''),
        channelId
      },
      android: { priority: 'high' },
      apns: {
        headers: { 'apns-priority': '5', 'apns-push-type': 'background' },
        payload: { aps: { 'content-available': 1 } }
      }
    });
  }
);
