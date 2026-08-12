// تركنا الصفحة فعّالة (لا redirect) — المحرّك يعمل بالخلفية لكن المشرف
// يحتاج زر تشخيص + bootstrap + tick + متابعة log. الصفحة client-only لأنّها
// تستدعي endpoints المحميّة بـ Firebase ID Token عبر authedJson.
export const ssr = false;
