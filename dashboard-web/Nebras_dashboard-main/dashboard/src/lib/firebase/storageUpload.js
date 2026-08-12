/**
 * رفع الملف إلى Firebase Storage ثم تسجيل الرابط في Cloud Firestore.
 * يُستدعى من orchestrator الرفع بدل التوقيع المباشر لـ R2.
 */
import {
  ref,
  uploadBytes,
  uploadBytesResumable,
  getDownloadURL,
  deleteObject,
} from "firebase/storage";
import { serverTimestamp } from "firebase/firestore";
import { getFirebaseStorage, getNebrasFirestore } from "./client.js";
import { clientFsWriteFileMirrorBoth } from "./nebrasUnifiedFirestoreClient.js";
import { stripUndefinedDeep } from "$lib/nebrasUnifiedSanitize.js";

/** أسماء المجموعات السابقة في RTDB (للتوافق مع الوثائق والمراجع الخارجية) */
export const FIREBASE_UPLOADS_RTDB_PATH = "dashboard_uploads";
export const FIREBASE_UPLOADS_FALLBACK_RTDB_PATH = "content_unified/files";

/** هدف حجم القطعة لرفع Firebase القابل للاستئناف (وثائقي — الـ SDK يدير التجزئة داخلياً). */
export const FIREBASE_RESUMABLE_CHUNK_TARGET_BYTES = 8 * 1024 * 1024;

function sanitizeFileSegment(name) {
  return String(name || "file")
    .replace(/[#$\[\]./]/g, "_")
    .slice(0, 180);
}

/**
 * Upload an optional thumbnail image for a content record. Returns the download URL
 * or `null` if no file was provided. The URL must be written into
 * `metadata.thumbnail` so the mobile app (which reads `metadata.thumbnail` /
 * root-level `thumbnail`) can render it.
 *
 * @param {string|number} fileId
 * @param {File|null|undefined} thumbnail
 * @returns {Promise<string|null>}
 */
export async function uploadContentThumbnail(fileId, thumbnail) {
  if (!thumbnail || typeof thumbnail !== "object" || !("size" in thumbnail)) {
    return null;
  }
  const storage = getFirebaseStorage();
  if (!storage) {
    throw new Error(
      "Firebase غير مهيأ. تحقق من متغيرات VITE_FIREBASE_* في .env",
    );
  }
  const safe = sanitizeFileSegment(thumbnail.name || "thumbnail");
  const path = `dashboard/content/${fileId}/thumbnail_${Date.now()}_${safe}`;
  const thumbRef = ref(storage, path);
  await uploadBytes(thumbRef, thumbnail, {
    contentType: thumbnail.type || "image/jpeg",
  });
  return getDownloadURL(thumbRef);
}

function buildMobileCompatibleFields(metadata, downloadUrl) {
  const normalized = metadata && typeof metadata === "object" ? metadata : {};
  const contentType =
    String(normalized.content_type || "document")
      .trim()
      .toLowerCase() || "document";
  const sourceFields = {
    sourceUrl: downloadUrl,
    source_url: downloadUrl,
    file_url: downloadUrl,
  };
  if (contentType === "audio") sourceFields.audio_url = downloadUrl;
  if (contentType === "video") sourceFields.video_url = downloadUrl;
  return {
    id: normalized.id || undefined,
    title: normalized.title || undefined,
    description: normalized.description || undefined,
    author: normalized.author || undefined,
    thumbnail: normalized.thumbnail || undefined,
    content_type: normalized.content_type || undefined,
    subsection: normalized.subsection,
    subsection_name:
      normalized.subsection_name || normalized.subsection_title || undefined,
    secondary_subsection: normalized.secondary_subsection,
    secondary_subsection_name:
      normalized.secondary_subsection_name ||
      normalized.secondary_subsection_title ||
      undefined,
    main_section: normalized.main_section,
    main_section_id: normalized.main_section_id,
    main_section_name: normalized.main_section_name,
    ...sourceFields,
  };
}

/**
 * المرحلة الأولى من الرفع: تحميل البايتات إلى Firebase Storage فقط (دون كتابة
 * أي سجل في RTDB). تُعاد رابط التنزيل ومسار التخزين ليُستخدما لاحقاً بعد
 * انتهاء رفع الـ thumbnail بالتوازي. يسمح هذا التقسيم بتشغيل رفعَي الـ
 * thumbnail والملف الرئيسي بالتوازي ثم كتابة سجلّ RTDB مرّة واحدة بعد
 * اكتمالهما.
 *
 * @param {File} file
 * @param {string|number} fileId
 * @param {{ onProgress: (n: number) => void, isAborted: () => boolean, onTaskCreated?: (task: import('firebase/storage').UploadTask) => void }} opts
 * @returns {Promise<{ downloadUrl: string, storagePath: string }>}
 */
export async function firebaseUploadFileToStorage(file, fileId, opts) {
  const { onProgress, isAborted, onTaskCreated } = opts;
  const storage = getFirebaseStorage();
  if (!storage) {
    throw new Error(
      "Firebase غير مهيأ. تحقق من متغيرات VITE_FIREBASE_* في .env",
    );
  }

  const safe = sanitizeFileSegment(file.name);
  const storagePath = `dashboard/content/${fileId}/${Date.now()}_${safe}`;
  const storageRef = ref(storage, storagePath);
  const contentType = file.type || "application/octet-stream";
  const task = uploadBytesResumable(storageRef, file, {
    contentType,
    customMetadata: {
      chunkTargetBytes: String(FIREBASE_RESUMABLE_CHUNK_TARGET_BYTES),
    },
  });
  onTaskCreated?.(task);

  await new Promise((resolve, reject) => {
    task.on(
      "state_changed",
      (snap) => {
        if (isAborted()) {
          task.cancel();
          return;
        }
        const total = snap.totalBytes || file.size || 1;
        onProgress((snap.bytesTransferred / total) * 100);
      },
      (err) => {
        if (err?.code === "storage/canceled")
          reject(new Error("Upload aborted"));
        else reject(err);
      },
      () => resolve(),
    );
  });

  if (isAborted()) throw new Error("Upload aborted");

  const downloadUrl = await getDownloadURL(task.snapshot.ref);
  return { downloadUrl, storagePath };
}

/**
 * المرحلة الثانية من الرفع: كتابة سجل الملف في RTDB. تُستدعى بعد انتهاء
 * رفع الملف الرئيسي ورفع الـ thumbnail (إن وُجد) بالتوازي، لضمان أن
 * `metadata.thumbnail` يحتوي رابط الـ thumbnail النهائي قبل الكتابة.
 *
 * @param {{ fileId: string|number, file: File, downloadUrl: string, storagePath: string, metadata: Record<string, unknown> }} params
 * @returns {Promise<string>} يُعيد downloadUrl
 */
export async function firebaseWriteFileRecord({
  fileId,
  file,
  downloadUrl,
  storagePath,
  metadata,
}) {
  const fsdb = getNebrasFirestore();
  if (!fsdb) {
    throw new Error(
      "Firebase Firestore غير مهيأ. تحقق من متغيرات VITE_FIREBASE_* في .env",
    );
  }

  const compatibleFields = buildMobileCompatibleFields(metadata, downloadUrl);

  const meta =
    metadata && typeof metadata === "object" ? metadata : {};
  const payload = stripUndefinedDeep({
    fileId,
    id: fileId,
    downloadUrl,
    filename: file.name,
    fileType: file.type || null,
    fileSize: file.size,
    metadata: meta,
    storagePath,
    createdAt: serverTimestamp(),
    ...(meta.selectionOrder != null
      ? { selectionOrder: meta.selectionOrder }
      : {}),
    ...(meta.selectionIndex != null
      ? { selectionIndex: meta.selectionIndex }
      : {}),
    ...(meta.batchId ? { batchId: meta.batchId } : {}),
    ...(meta.content_sha256 ? { content_sha256: meta.content_sha256 } : {}),
    // ⚖️ بيانات الامتثال للحقوق (اختياريّة للرفع اليدوي). تُكتَب فقط حين
    // يملؤها المشرف، فلا تتأثّر أيّ رفعات قائمة لا تمرّر هذه الحقول. يقرأها
    // التطبيق لعرض الإسناد ولحجب 'rejected'.
    ...(meta.source_name ? { __source_provider: String(meta.source_name) } : {}),
    ...(meta.license_status
      ? { __license_status: String(meta.license_status) }
      : {}),
    ...(meta.license_name ? { __license: String(meta.license_name) } : {}),
    ...(meta.license_url ? { __license_url: String(meta.license_url) } : {}),
    ...compatibleFields,
  });

  await clientFsWriteFileMirrorBoth(fileId, payload);

  return downloadUrl;
}

/**
 * حذف كائن من Storage (استرداد عند فشل كتابة Firestore).
 * @param {string} storagePath
 */
export async function firebaseDeleteStoragePath(storagePath) {
  const path = String(storagePath || "").trim();
  if (!path) return;
  const storage = getFirebaseStorage();
  if (!storage) return;
  try {
    await deleteObject(ref(storage, path));
  } catch (err) {
    console.warn("[storageUpload] rollback delete failed:", err);
  }
}

/**
 * @param {File} file
 * @param {string|number} fileId من الخادم بعد initiate
 * @param {Record<string, unknown>} metadata نفس metadata النموذج الحالي
 * @param {{ onProgress: (n: number) => void, isAborted: () => boolean, onTaskCreated?: (task: import('firebase/storage').UploadTask) => void }} opts
 *
 * محفوظة لمسار استئناف الرفع الفردي ([createResumeUploader] في fileUpload.js).
 */
export async function firebaseUploadContentFile(file, fileId, metadata, opts) {
  const { downloadUrl, storagePath } = await firebaseUploadFileToStorage(
    file,
    fileId,
    opts,
  );
  await firebaseWriteFileRecord({
    fileId,
    file,
    downloadUrl,
    storagePath,
    metadata,
  });
  return downloadUrl;
}
