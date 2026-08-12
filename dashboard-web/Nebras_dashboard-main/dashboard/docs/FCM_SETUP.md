# تفعيل إشعارات FCM في لوحة التحكم

نظام الإشعارات يعمل **Topic-based**: لوحة التحكّم ترسل رسالة FCM إلى Topic باسم
`nebras_all_users`، وكلّ جهاز يشغّل التطبيق يكون مشتركاً في هذا الـ Topic تلقائياً.

## الخطوات

### 1) استخراج مفتاح حساب خدمة Firebase

1. افتح [Firebase Console](https://console.firebase.google.com/) → اختر المشروع.
2. Settings ⚙️ → **Project settings** → تبويب **Service accounts**.
3. اضغط **Generate new private key** → احفظ ملف `service-account.json` في مكان آمن.

> الملف يحتوي `private_key` ولا يجب أبداً رفعه إلى Git أو كشفه للمتصفّح.

### 2) إضافته إلى `.env`

افتح `dashboard/.env` (انسخ من `.env.example` إن لم يكن موجوداً)، ثم أضِف:

```ini
# ضع محتوى الملف كسلسلة JSON واحدة. استخدم أداة مثل:
#   Get-Content service-account.json -Raw | ConvertTo-Json -Compress   (PowerShell)
# أو Node لتحويل الأسطر الجديدة داخل private_key إلى \n.
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"...","..."}

# (بديل) أو ضع مسار الملف على القرص:
# FIREBASE_SERVICE_ACCOUNT_PATH=C:/secrets/service-account.json

# اسم الـ Topic — يجب أن يطابق kBroadcastTopic في firebase_notification_datasource.dart
FCM_BROADCAST_TOPIC=nebras_all_users
```

ثم أعد تشغيل خادم التطوير:

```bash
npm run dev
```

### 3) التحقق

- من لوحة التحكّم: أنشئ قسماً جديداً أو ارفع ملفاً جديداً.
- الخادم يرسل POST إلى `/api/notify` داخلياً.
- الأجهزة المشتركة تتلقّى إشعاراً باسم "تمّت إضافة …".

### السلوك عند غياب المفتاح

إن لم يُضبط `FIREBASE_SERVICE_ACCOUNT_JSON`، مسار `/api/notify` يعود بـ **501** ومساعد
`notifyEvents.js` يتجاهل ذلك بصمت. **الرفع وإنشاء الأقسام يعملان بشكل طبيعي تماماً**،
لكن لا تُبثّ إشعارات — هذا متعمّد حتى لا يتعطّل عمل الموقع عند غياب الإعدادات.

## سجلّ الرسائل

- Success: `200 { ok: true, messageId: "projects/.../messages/..." }`
- Not configured: `501 { ok: false, reason: "not_configured" }`
- Bad payload: `400 { ok: false, reason: "missing_title_or_body" }`
- FCM API error: `502 { ok: false, reason: "fcm_send_failed", message: "..." }`

## Topic واحد لكل المستخدمين

ميزة هذا النمط:
- لا حاجة لتخزين tokens الأجهزة في قاعدة البيانات.
- التطبيق يشترك في `nebras_all_users` تلقائياً عند الإقلاع.
- البثّ لحظي وبدون صيانة.

إذا أردت لاحقاً استهداف مجموعات محدّدة (مثلاً "مشتركو قسم صوتيات فقط")، غيّر اسم الـ
Topic في صفحات الاستدعاء (parameter `topic` داخل `postNotification`) واستعمل
`FirebaseMessaging.subscribeToTopic(...)` في التطبيق عند اهتمام المستخدم بالقسم.
