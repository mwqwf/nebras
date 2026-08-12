"use client"

import { Navbar } from "@/components/navbar"
import { Footer } from "@/components/footer"
import { LocaleProvider, useLocale } from "@/components/locale-provider"

// Note: Metadata is handled in a separate metadata.ts file or via generateMetadata for client components
// For this client component, we set document title dynamically

function PrivacyContent() {
  const { locale, t } = useLocale()
  
  // Privacy policy content in all three languages
  const content = {
    ar: {
      title: "سياسة الخصوصية وشروط الاستخدام",
      lastUpdated: "آخر تحديث",
      privacyPolicy: {
        title: "سياسة الخصوصية",
        sections: [
          {
            title: "١. مقدمة",
            content: "مرحباً بكم في نِبراس. نحن ملتزمون بحماية خصوصيتكم وضمان تجربة إيجابية عند استخدام تطبيقنا. توضح سياسة الخصوصية هذه كيفية تعاملنا مع معلوماتكم عند استخدام تطبيقنا المتاح على متجر Google Play."
          },
          {
            title: "٢. المعلومات التي نجمعها",
            content: "نجمع الحد الأدنى من البيانات اللازمة لتقديم خدماتنا. نوضح أدناه بالتفصيل كل نوع من البيانات التي نجمعها:",
            subsections: [
              {
                title: "أ. معلومات المصادقة (تسجيل الدخول عبر Google)",
                items: [
                  "الاسم الكامل من حساب Google الخاص بك",
                  "عنوان البريد الإلكتروني",
                  "صورة الملف الشخصي (إن وجدت)",
                  "معرّف المستخدم الفريد (User ID) الذي يُنشئه Firebase"
                ],
                purpose: "الغرض: إنشاء حسابك والتعرف عليك عبر الجلسات المختلفة."
              },
              {
                title: "ب. رموز الإشعارات (FCM Tokens)",
                items: [
                  "نجمع رموز Firebase Cloud Messaging (FCM) الخاصة بجهازك",
                  "تُرسل هذه الرموز إلى خادمنا الخاص لتمكين إرسال الإشعارات إليك",
                  "تُستخدم هذه الرموز حصرياً لإرسال إشعارات التطبيق إليك",
                  "قد تشمل الإشعارات: تنبيهات المحتوى الجديد، تحديثات التطبيق، أو رسائل مهمة"
                ],
                purpose: "الغرض: تمكين خدمة الإشعارات الفورية على جهازك.",
                note: "ملاحظة: يُرسل رمز FCM إلى خادمنا (بالإضافة إلى Firebase) لتمكيننا من إرسال الإشعارات المخصصة."
              },
              {
                title: "ج. بيانات التخصيص المحلية (لا تُجمع على خوادمنا)",
                items: [
                  "الكتب التي تتصفحها وتقرأها",
                  "الفيديوهات التي تشاهدها ومدة المشاهدة",
                  "المحتوى الذي تحفظه في مكتبتك الشخصية",
                  "الأقسام والمواضيع التي تزورها بشكل متكرر",
                  "آخر صفحة قرأتها في كل كتاب (لاستئناف القراءة)"
                ],
                purpose: "الغرض: تخصيص تجربتك وتقديم توصيات محتوى ملائمة لاهتماماتك.",
                note: "ملاحظة مهمة: هذه البيانات تُخزَّن محلياً على جهازك فقط ولا تُرسل إلى خوادمنا أو أي طرف ثالث. نحن لا نجمع هذه البيانات - التخصيص يتم بالكامل على مستوى جهازك."
              },
              {
                title: "د. بلاغات المحتوى",
                items: [
                  "عند الإبلاغ عن محتوى مخالف، نحتفظ بمعرّف المستخدم الخاص بك (reporterUid) مرتبطاً بالبلاغ",
                  "نوع البلاغ وتفاصيله (حقوق نشر، محتوى غير لائق، إلخ)",
                  "معرّف المحتوى المُبلَّغ عنه",
                  "تاريخ ووقت البلاغ"
                ],
                purpose: "الغرض: متابعة البلاغات والتحقق منها ومنع سوء الاستخدام.",
                note: "ملاحظة: البلاغات مرتبطة بهويتك لضمان مصداقية البلاغات ومنع الإساءة."
              },
              {
                title: "هـ. تشغيل الصوت في الخلفية",
                items: [
                  "يستخدم التطبيق خدمة تشغيل في المقدمة (Foreground Service) لتشغيل الصوت في الخلفية",
                  "هذه الخدمة تُستخدم حصرياً لتشغيل الوسائط (Media Playback) - الكتب الصوتية والمحتوى الصوتي",
                  "تظهر إشعار دائم أثناء تشغيل الصوت للتحكم في التشغيل",
                  "لا تُجمع أي بيانات إضافية من خلال هذه الخدمة"
                ],
                purpose: "الغرض: تمكينك من الاستماع للمحتوى الصوتي حتى عند إغلاق التطبيق أو قفل الشاشة.",
                note: "ملاحظة: هذه الميزة لا تتعلق بالتتبع أو جمع البيانات - إنها فقط لتشغيل الصوت."
              }
            ]
          },
          {
            title: "٣. كيف نستخدم معلوماتك",
            content: "نستخدم المعلومات التي نجمعها للأغراض التالية فقط:",
            items: [
              "إنشاء حسابك والحفاظ عليه",
              "تخصيص صفحتك الرئيسية بناءً على اهتماماتك",
              "تقديم توصيات كتب وفيديوهات ذات صلة",
              "حفظ تقدمك في القراءة واستئنافها لاحقاً",
              "إرسال إشعارات حول المحتوى الجديد الذي قد يهمك",
              "تحسين التطبيق وتجربة المستخدم بشكل عام"
            ]
          },
          {
            title: "٤. تخزين البيانات ومدة الاحتفاظ بها",
            content: "نخزن بياناتك بشكل آمن على خوادم Firebase (المملوكة لشركة Google) ونحتفظ بها وفق السياسة التالية:",
            items: [
              "بيانات الحساب: نحتفظ بها طوال فترة نشاط حسابك",
              "بيانات التخصيص: تبقى محلياً على جهازك ولا نحتفظ بها على خوادمنا",
              "رموز FCM: تُحدَّث تلقائياً وتُحذف القديمة منها",
              "المحتوى المحفوظ: يبقى حتى تحذفه أنت أو تحذف حسابك"
            ],
            note: "عند حذف حسابك، نحذف جميع بياناتك خلال 30 يوما�� كحد أقصى."
          },
          {
            title: "٥. البيانات التي لا نجمعها",
            content: "نؤكد أننا لا نجمع أبداً:",
            items: [
              "بيانات الموقع الجغرافي",
              "جهات الاتصال أو دفتر العناوين",
              "المعلومات المالية أو بيانات الدفع",
              "معرّفات الجهاز لأغراض الإعلان (Advertising ID)",
              "البيانات الصحية أو الحيوية",
              "الرسائل أو الصور أو الملفات الشخصية",
              "سجل التصفح خارج التطبيق"
            ]
          },
          {
            title: "٦. مشاركة البيانات والإفصاح عنها",
            content: "نحن لا نبيع أو نتاجر أو نؤجر بياناتك الشخصية لأي طرف ثالث.",
            subsections: [
              {
                title: "نشارك البيانات فقط في الحالات التالية:",
                items: [
                  "مع خدمات Firebase/Google لتشغيل البنية التحتية للتطبيق (المصادقة، قاعدة البيانات، الإشعارات)",
                  "عند الطلب القانوني من جهات إنفاذ القانون وفق الإجراءات القانونية السليمة",
                  "لحماية حقوقنا أو سلامة مستخدمينا في حالات الضرورة القصوى"
                ]
              }
            ]
          },
          {
            title: "٧. أمان البيانات",
            content: "نطبق تدابير أمنية صارمة لحماية بياناتك:",
            items: [
              "تشفير البيانات أثناء النقل (TLS/SSL)",
              "قواعد أمان صارمة على قاعدة بيانات Firestore",
              "المصادقة الآمنة عبر بروتوكولات Google Sign-In",
              "عدم تخزين كلمات المرور (نعتمد كلياً على مصادقة Google)",
              "مراجعة دورية للأذونات والوصول"
            ]
          },
          {
            title: "٨. حقوقك",
            content: "لديك الحقوق التالية فيما يتعلق ببياناتك:",
            items: [
              "الوصول: يمكنك طلب نسخة من بياناتك المخزنة لدينا",
              "التصحيح: يمكنك تحديث معلومات ملفك الشخصي عبر إعدادات حساب Google",
              "الحذف: يمكنك طلب حذف حسابك وجميع بياناتك المرتبطة به",
              "إلغاء الاشتراك: يمكنك إيقاف الإشعارات من إعدادات التطبيق",
              "سحب الموافقة: يمكنك إلغاء أذونات تسجيل الدخول من إعدادات حساب Google"
            ]
          },
          {
            title: "٩. كيفية حذف حسابك وبياناتك",
            content: "نوفر لجميع المستخدمين إمكانية حذف حساباتهم مباشرة من داخل التطبيق نفسه، دون الحاجة للذهاب إلى أي موقع خارجي أو اتخاذ أي إجراءات إضافية. هذه الميزة متاحة لجميع المستخدمين بشكل كامل.",
            subsections: [
              {
                title: "الطريقة الرئيسية: من داخل التطبيق مباشرة (موصى بها)",
                items: [
                  "افتح التطبيق وانتقل إلى الإعدادات",
                  "اضغط على \"حذف الحساب\"",
                  "أكد رغبتك في الحذف",
                  "سيتم حذف جميع بياناتك فوراً وبشكل نهائي"
                ],
                note: "هذه هي الطريقة الأسرع والأسهل - لا تحتاج لأي شيء آخر."
              },
              {
                title: "طريقة بديلة: عبر البريد الإلكتروني (في حال عدم تمكنك من الوصول للتطبيق)",
                items: [
                  "أرسل طلب حذف إلى: oroekekdkdjjddjjdke@gmail.com",
                  "اذكر عنوان بريدك الإلكتروني المرتبط بالحساب",
                  "سنعالج طلبك خلال 7 أيام عمل",
                  "ستتلقى تأكيداً عند اكتمال الحذف"
                ]
              }
            ],
            note: "البيانات التي تُحذف تشمل: معلومات الملف الشخصي، رموز FCM، المحتوى المحفوظ، وجميع البيانات المرتبطة بحسابك على خوادمنا. بيانات التخصيص المحلية على جهازك يمكنك حذفها بإلغاء تثبيت التطبيق. ملاحظة: قد تبقى بعض البلاغات المقدمة منك مجهولة الهوية (بدون ربطها بحسابك) للحفاظ على سلامة المحتوى."
          },
          {
            title: "١٠. خصوصية الأطفال",
            content: "تطبيقنا مصمم للجمهور العام. نحن لا نجمع عن قصد معلومات شخصية من الأطفال دون سن 13 عاماً. إذا علمنا أن طفلاً دون 13 عاماً قد زودنا بمعلومات شخصية، سنحذفها فوراً. إذا كنت والداً أو وصياً وتعتقد أن طفلك قد قدم لنا معلومات، يرجى التواصل معنا."
          },
          {
            title: "١١. التغييرات على سياسة الخصوصية",
            content: "قد نحدث هذه السياسة من وقت لآخر. سنخطرك بأي تغييرات جوهرية عبر:",
            items: [
              "إشعار داخل التطبيق",
              "تحديث تاريخ \"آخر تحديث\" في هذه الصفحة",
              "إشعار عبر البريد الإلكتروني للتغييرات الكبيرة"
            ],
            note: "استمرارك في استخدام التطبيق بعد نشر التغييرات يعني موافقتك على السياسة المحدثة."
          }
        ]
      },
      termsOfService: {
        title: "شروط الاستخدام",
        sections: [
          {
            title: "١. قبول الشروط",
            content: "بتحميل أو تثبيت أو استخدام تطبيق نِبراس، فإنك توافق على الالتزام بشروط الاستخدام هذه. إذا كنت لا توافق على هذه الشروط، يرجى عدم استخدام تطبيقنا."
          },
          {
            title: "٢. وصف الخدمة",
            content: "نِبراس هو منصة لمشاركة المعرفة توفر الوصول إلى محتوى تعليمي يشمل الكتب والفيديوهات ومواد أخرى تتعلق بالمعارف الدينية من مختلف المذاهب الإسلامية، بالإضافة إلى العلوم الدنيوية. التطبيق متوفر بثلاث لغات: العربية والإنجليزية والفرنسية."
          },
          {
            title: "٣. حسابات المستخدمين",
            content: "تسجيل الدخول في تطبيق نِبراس اختياري وليس إلزامياً. يمكنك استخدام التطبيق كضيف دون إنشاء حساب. إذا اخترت تسجيل الدخول باستخدام حساب Google، فإنك توافق على:",
            items: [
              "تقديم معلومات دقيقة وكاملة",
              "الحفاظ على أمان بيانات اعتماد حسابك",
              "تحمل المسؤولية عن جميع الأنشطة التي تحدث تحت حسابك",
              "إخطارنا فوراً بأي استخدام غير مصرح به لحسابك"
            ],
            note: "ملاحظة: بعض الميزات مثل حفظ المحتوى والتخصيص قد تتطلب تسجيل الدخول."
          },
          {
            title: "٤. الاستخدام المقبول",
            content: "أنت توافق على استخدام نِبراس فقط للأغراض المشروعة ووفقاً لهذه الشروط. أنت توافق على عدم:",
            items: [
              "استخدام التطبيق بأي طريقة تنتهك القوانين أو اللوائح المعمول بها",
              "محاولة الوصول غير المصرح به إلى أي جزء من التطبيق",
              "التدخل في سلامة التطبيق أو أدائه أو تعطيله",
              "نسخ أو تعديل ��و توزيع أو إنشاء أعمال مشتقة من محتوانا دون إذن",
              "استخدام أنظمة أو برامج آلية لاستخراج البيانات من التطبيق"
            ]
          },
          {
            title: "٥. الملكية الفكرية",
            content: "المحتوى المتاح عبر نِبراس، بما في ذلك على سبيل المثال لا الحصر النصوص والرسومات وا����شعارات والصور والمحتوى الصوتي والمرئي، محمي بموجب قوانين حقوق النشر والعلامات التجارية وقوانين الملكية الفكرية الأخرى. يُقدم المحتوى للاستخدام التعليمي الشخصي غير التجاري فقط."
          },
          {
            title: "٦. إخلاء مسؤولية المحتوى",
            content: "يقدم نِبراس محتوى من مخ��لف المذاهب الإسلامية والعلوم الدنيوية لأغراض تعليمية. وجود أي محتوى لا يشكل تأييداً لأي وجهة نظر معينة. نشجع المستخدمين على التعامل مع جميع المحتوى بتفكير نقدي واستشارة العلماء المؤهلين للإرشاد الديني."
          },
          {
            title: "٧. التوفر والتحديثات",
            content: "نسعى للحفاظ على توفر نِبراس في جميع الأوقات، لكننا لا نضمن الوصول المتواصل إلى خدماتنا. قد نعدل أو نعلق أو نوقف أي جزء من التطبيق في أي وقت دون إشعار."
          },
          {
            title: "٨. تحديد المسؤولية",
            content: "إلى أقصى حد يسمح به القانون، لن يكون نِبراس ومطوروه مسؤولين عن أي أضرار غير مباشرة أو عرضية أ�� خاصة أو تبعية أو عقابية، بما في ذلك على سبيل المثال لا الحصر خسارة الأرباح أو البيانات أو الخسائر غير الملموسة الأخرى."
          },
          {
            title: "٩. التعويض",
            content: "أنت توافق على تعويض نِبراس ومطوريه والمسؤولين والموظفين والدفاع عنهم وحمايتهم من أي مطالبات ��و أضرار أو التزامات أو تكاليف تنشأ عن استخدامك للتطبيق أو انتهاكك لهذه الشروط."
          },
          {
            title: "١٠. التغييرات على الشروط",
            content: "نحتفظ بالحق في تعديل هذه الشروط في أي وقت. سيتم نشر التغييرات على هذه الصفحة مع تاريخ \"آخر تحديث\" محدث. استمرارك في استخدام التطبيق بعد إجراء التغييرات يشكل قبولاً للشروط المعدلة."
          }
        ]
      },
      contact: {
        title: "١١. التواصل معنا",
        content: "إذا كانت لديك أي أسئلة أو مخاوف بشأن سياسة الخصوصية أو شروط الاستخدام هذه، يرجى التواصل معنا عبر البريد الإلكتروني:"
      }
    },
    en: {
      title: "Privacy Policy and Terms of Service",
      lastUpdated: "Last updated",
      privacyPolicy: {
        title: "Privacy Policy",
        sections: [
          {
            title: "1. Introduction",
            content: "Welcome to Nibras. We are committed to protecting your privacy and ensuring a positive experience when using our application. This privacy policy explains how we handle your information when you use our app available on Google Play Store."
          },
          {
            title: "2. Information We Collect",
            content: "We collect the minimum data necessary to provide our services. Below we detail each type of data we collect:",
            subsections: [
              {
                title: "a. Authentication Information (Google Sign-In)",
                items: [
                  "Your full name from your Google account",
                  "Email address",
                  "Profile picture (if available)",
                  "Unique User ID generated by Firebase"
                ],
                purpose: "Purpose: To create your account and identify you across different sessions."
              },
              {
                title: "b. Notification Tokens (FCM Tokens)",
                items: [
                  "We collect Firebase Cloud Messaging (FCM) tokens from your device",
                  "These tokens are sent to our server to enable sending notifications to you",
                  "These tokens are used exclusively to send app notifications to you",
                  "Notifications may include: new content alerts, app updates, or important messages"
                ],
                purpose: "Purpose: To enable push notification service on your device.",
                note: "Note: FCM token is sent to our server (in addition to Firebase) to enable us to send customized notifications."
              },
              {
                title: "c. Local Personalization Data (Not Collected on Our Servers)",
                items: [
                  "Books you browse and read",
                  "Videos you watch and viewing duration",
                  "Content you save to your personal library",
                  "Sections and topics you frequently visit",
                  "Last page read in each book (to resume reading)"
                ],
                purpose: "Purpose: To personalize your experience and provide content recommendations relevant to your interests.",
                note: "Important Note: This data is stored locally on your device only and is not sent to our servers or any third party. We do not collect this data - personalization is done entirely on your device."
              },
              {
                title: "d. Content Reports",
                items: [
                  "When reporting inappropriate content, we retain your user ID (reporterUid) linked to the report",
                  "Report type and details (copyright, inappropriate content, etc.)",
                  "Identifier of the reported content",
                  "Date and time of the report"
                ],
                purpose: "Purpose: To follow up on reports, verify them, and prevent abuse.",
                note: "Note: Reports are linked to your identity to ensure report credibility and prevent misuse."
              },
              {
                title: "e. Background Audio Playback",
                items: [
                  "The app uses a Foreground Service for playing audio in the background",
                  "This service is used exclusively for Media Playback - audiobooks and audio content",
                  "A persistent notification appears during audio playback for playback control",
                  "No additional data is collected through this service"
                ],
                purpose: "Purpose: To enable you to listen to audio content even when the app is closed or the screen is locked.",
                note: "Note: This feature is not related to tracking or data collection - it is solely for audio playback."
              }
            ]
          },
          {
            title: "3. How We Use Your Information",
            content: "We use the information we collect for the following purposes only:",
            items: [
              "Creating and maintaining your account",
              "Personalizing your home page based on your interests",
              "Providing relevant book and video recommendations",
              "Saving your reading progress to resume later",
              "Sending notifications about new content that may interest you",
              "Improving the app and overall user experience"
            ]
          },
          {
            title: "4. Data Storage and Retention",
            content: "We securely store your data on Firebase servers (owned by Google) and retain it according to the following policy:",
            items: [
              "Account data: Retained throughout your account's active period",
              "Personalization data: Stays locally on your device and is not retained on our servers",
              "FCM tokens: Automatically updated and old ones deleted",
              "Saved content: Remains until you delete it or delete your account"
            ],
            note: "When you delete your account, we delete all your data within a maximum of 30 days."
          },
          {
            title: "5. Data We Do Not Collect",
            content: "We confirm that we never collect:",
            items: [
              "Geographic location data",
              "Contacts or address book",
              "Financial information or payment data",
              "Device identifiers for advertising purposes (Advertising ID)",
              "Health or biometric data",
              "Messages, photos, or personal files",
              "Browsing history outside the app"
            ]
          },
          {
            title: "6. Data Sharing and Disclosure",
            content: "We do not sell, trade, or rent your personal data to any third party.",
            subsections: [
              {
                title: "We share data only in the following cases:",
                items: [
                  "With Firebase/Google services to operate the app infrastructure (authentication, database, notifications)",
                  "Upon legal request from law enforcement following proper legal procedures",
                  "To protect our rights or the safety of our users in cases of extreme necessity"
                ]
              }
            ]
          },
          {
            title: "7. Data Security",
            content: "We implement strict security measures to protect your data:",
            items: [
              "Data encryption during transit (TLS/SSL)",
              "Strict security rules on Firestore database",
              "Secure authentication via Google Sign-In protocols",
              "No password storage (we rely entirely on Google authentication)",
              "Periodic review of permissions and access"
            ]
          },
          {
            title: "8. Your Rights",
            content: "You have the following rights regarding your data:",
            items: [
              "Access: You can request a copy of your stored data",
              "Correction: You can update your profile information via Google account settings",
              "Deletion: You can request deletion of your account and all associated data",
              "Opt-out: You can disable notifications from app settings",
              "Withdraw consent: You can revoke sign-in permissions from Google account settings"
            ]
          },
          {
            title: "9. How to Delete Your Account and Data",
            content: "We provide all users with the ability to delete their accounts directly from within the app itself, without needing to visit any external website or take any additional steps. This feature is fully available to all users.",
            subsections: [
              {
                title: "Primary Method: Directly from within the app (Recommended)",
                items: [
                  "Open the app and go to Settings",
                  "Tap on \"Delete Account\"",
                  "Confirm your deletion request",
                  "All your data will be deleted immediately and permanently"
                ],
                note: "This is the fastest and easiest method - you don't need anything else."
              },
              {
                title: "Alternative Method: Via email (if you cannot access the app)",
                items: [
                  "Send a deletion request to: oroekekdkdjjddjjdke@gmail.com",
                  "Include your email address associated with the account",
                  "We will process your request within 7 business days",
                  "You will receive confirmation when deletion is complete"
                ]
              }
            ],
            note: "Data that will be deleted includes: profile information, FCM tokens, saved content, and all data associated with your account on our servers. Local personalization data on your device can be deleted by uninstalling the app. Note: Some reports you submitted may remain anonymized (without linking to your account) to maintain content integrity."
          },
          {
            title: "10. Children's Privacy",
            content: "Our app is designed for a general audience. We do not knowingly collect personal information from children under 13 years old. If we learn that a child under 13 has provided us with personal information, we will delete it immediately. If you are a parent or guardian and believe your child has provided us with information, please contact us."
          },
          {
            title: "11. Changes to Privacy Policy",
            content: "We may update this policy from time to time. We will notify you of any material changes via:",
            items: [
              "In-app notification",
              "Updating the \"Last updated\" date on this page",
              "Email notification for significant changes"
            ],
            note: "Your continued use of the app after posting changes means you accept the updated policy."
          }
        ]
      },
      termsOfService: {
        title: "Terms of Service",
        sections: [
          {
            title: "1. Acceptance of Terms",
            content: "By downloading, installing, or using the Nibras application, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use our app."
          },
          {
            title: "2. Service Description",
            content: "Nibras is a knowledge-sharing platform providing access to educational content including books, videos, and other materials related to religious knowledge from various Islamic schools of thought, as well as worldly sciences. The app is available in three languages: Arabic, English, and French."
          },
          {
            title: "3. User Accounts",
            content: "Signing in to the Nibras app is optional and not mandatory. You can use the app as a guest without creating an account. If you choose to sign in using your Google account, you agree to:",
            items: [
              "Provide accurate and complete information",
              "Maintain the security of your account credentials",
              "Be responsible for all activities that occur under your account",
              "Notify us immediately of any unauthorized use of your account"
            ],
            note: "Note: Some features such as saving content and personalization may require signing in."
          },
          {
            title: "4. Acceptable Use",
            content: "You agree to use Nibras only for lawful purposes and in accordance with these terms. You agree not to:",
            items: [
              "Use the app in any way that violates applicable laws or regulations",
              "Attempt unauthorized access to any part of the app",
              "Interfere with or disrupt the app's integrity or performance",
              "Copy, modify, distribute, or create derivative works from our content without permission",
              "Use automated systems or software to extract data from the app"
            ]
          },
          {
            title: "5. Intellectual Property",
            content: "Content available through Nibras, including but not limited to text, graphics, logos, images, and audio/video content, is protected by copyright, trademark, and other intellectual property laws. Content is provided for personal, non-commercial educational use only."
          },
          {
            title: "6. Content Disclaimer",
            content: "Nibras provides content from various Islamic schools of thought and worldly sciences for educational purposes. The presence of any content does not constitute endorsement of any particular viewpoint. We encourage users to approach all content with critical thinking and consult qualified scholars for religious guidance."
          },
          {
            title: "7. Availability and Updates",
            content: "We strive to maintain Nibras availability at all times, but we do not guarantee uninterrupted access to our services. We may modify, suspend, or discontinue any part of the app at any time without notice."
          },
          {
            title: "8. Limitation of Liability",
            content: "To the maximum extent permitted by law, Nibras and its developers shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including but not limited to loss of profits, data, or other intangible losses."
          },
          {
            title: "9. Indemnification",
            content: "You agree to indemnify, defend, and hold harmless Nibras, its developers, officers, and employees from any claims, damages, liabilities, or costs arising from your use of the app or your violation of these terms."
          },
          {
            title: "10. Changes to Terms",
            content: "We reserve the right to modify these terms at any time. Changes will be posted on this page with an updated \"Last updated\" date. Your continued use of the app after changes are made constitutes acceptance of the modified terms."
          }
        ]
      },
      contact: {
        title: "11. Contact Us",
        content: "If you have any questions or concerns about this Privacy Policy or Terms of Service, please contact us via email:"
      }
    },
    fr: {
      title: "Politique de confidentialite et Conditions d'utilisation",
      lastUpdated: "Derniere mise a jour",
      privacyPolicy: {
        title: "Politique de confidentialite",
        sections: [
          {
            title: "1. Introduction",
            content: "Bienvenue sur Nibras. Nous nous engageons a proteger votre vie privee et a garantir une experience positive lors de l'utilisation de notre application. Cette politique de confidentialite explique comment nous traitons vos informations lorsque vous utilisez notre application disponible sur Google Play Store."
          },
          {
            title: "2. Informations que nous collectons",
            content: "Nous collectons le minimum de donnees necessaires pour fournir nos services. Ci-dessous, nous detaillons chaque type de donnees que nous collectons :",
            subsections: [
              {
                title: "a. Informations d'authentification (Connexion Google)",
                items: [
                  "Votre nom complet de votre compte Google",
                  "Adresse e-mail",
                  "Photo de profil (si disponible)",
                  "Identifiant utilisateur unique genere par Firebase"
                ],
                purpose: "Objectif : Creer votre compte et vous identifier a travers differentes sessions."
              },
              {
                title: "b. Jetons de notification (Jetons FCM)",
                items: [
                  "Nous collectons les jetons Firebase Cloud Messaging (FCM) de votre appareil",
                  "Ces jetons sont envoyes a notre serveur pour permettre l'envoi de notifications",
                  "Ces jetons sont utilises exclusivement pour vous envoyer des notifications de l'application",
                  "Les notifications peuvent inclure : alertes de nouveau contenu, mises a jour de l'application ou messages importants"
                ],
                purpose: "Objectif : Activer le service de notification push sur votre appareil.",
                note: "Note : Le jeton FCM est envoye a notre serveur (en plus de Firebase) pour nous permettre d'envoyer des notifications personnalisees."
              },
              {
                title: "c. Donnees de personnalisation locales (Non collectees sur nos serveurs)",
                items: [
                  "Livres que vous parcourez et lisez",
                  "Videos que vous regardez et duree de visionnage",
                  "Contenu que vous enregistrez dans votre bibliotheque personnelle",
                  "Sections et sujets que vous visitez frequemment",
                  "Derniere page lue dans chaque livre (pour reprendre la lecture)"
                ],
                purpose: "Objectif : Personnaliser votre experience et fournir des recommandations de contenu pertinentes a vos interets.",
                note: "Note importante : Ces donnees sont stockees localement sur votre appareil uniquement et ne sont pas envoyees a nos serveurs ni a des tiers. Nous ne collectons pas ces donnees - la personnalisation se fait entierement sur votre appareil."
              },
              {
                title: "d. Signalements de contenu",
                items: [
                  "Lors du signalement d'un contenu inapproprie, nous conservons votre identifiant utilisateur (reporterUid) lie au signalement",
                  "Type et details du signalement (droits d'auteur, contenu inapproprie, etc.)",
                  "Identifiant du contenu signale",
                  "Date et heure du signalement"
                ],
                purpose: "Objectif : Suivre les signalements, les verifier et prevenir les abus.",
                note: "Note : Les signalements sont lies a votre identite pour garantir la credibilite des signalements et prevenir les abus."
              },
              {
                title: "e. Lecture audio en arriere-plan",
                items: [
                  "L'application utilise un Foreground Service pour lire l'audio en arriere-plan",
                  "Ce service est utilise exclusivement pour la lecture multimedia - livres audio et contenu audio",
                  "Une notification persistante apparait pendant la lecture audio pour controler la lecture",
                  "Aucune donnee supplementaire n'est collectee via ce service"
                ],
                purpose: "Objectif : Vous permettre d'ecouter du contenu audio meme lorsque l'application est fermee ou l'ecran est verrouille.",
                note: "Note : Cette fonctionnalite n'est pas liee au suivi ou a la collecte de donnees - elle sert uniquement a la lecture audio."
              }
            ]
          },
          {
            title: "3. Comment nous utilisons vos informations",
            content: "Nous utilisons les informations que nous collectons uniquement aux fins suivantes :",
            items: [
              "Creer et maintenir votre compte",
              "Personnaliser votre page d'accueil en fonction de vos interets",
              "Fournir des recommandations pertinentes de livres et videos",
              "Enregistrer votre progression de lecture pour reprendre plus tard",
              "Envoyer des notifications sur le nouveau contenu susceptible de vous interesser",
              "Ameliorer l'application et l'experience utilisateur globale"
            ]
          },
          {
            title: "4. Stockage et conservation des donnees",
            content: "Nous stockons vos donnees en toute securite sur les serveurs Firebase (propriete de Google) et les conservons selon la politique suivante :",
            items: [
              "Donnees de compte : Conservees pendant toute la periode d'activite de votre compte",
              "Donnees de personnalisation : Restent localement sur votre appareil et ne sont pas conservees sur nos serveurs",
              "Jetons FCM : Automatiquement mis a jour et les anciens supprimes",
              "Contenu enregistre : Reste jusqu'a ce que vous le supprimiez ou supprimiez votre compte"
            ],
            note: "Lorsque vous supprimez votre compte, nous supprimons toutes vos donnees dans un delai maximum de 30 jours."
          },
          {
            title: "5. Donnees que nous ne collectons pas",
            content: "Nous confirmons que nous ne collectons jamais :",
            items: [
              "Donnees de localisation geographique",
              "Contacts ou carnet d'adresses",
              "Informations financieres ou donnees de paiement",
              "Identifiants d'appareil a des fins publicitaires (Advertising ID)",
              "Donnees de sante ou biometriques",
              "Messages, photos ou fichiers personnels",
              "Historique de navigation en dehors de l'application"
            ]
          },
          {
            title: "6. Partage et divulgation des donnees",
            content: "Nous ne vendons, n'echangeons ni ne louons vos donnees personnelles a des tiers.",
            subsections: [
              {
                title: "Nous partageons des donnees uniquement dans les cas suivants :",
                items: [
                  "Avec les services Firebase/Google pour faire fonctionner l'infrastructure de l'application (authentification, base de donnees, notifications)",
                  "Sur demande legale des forces de l'ordre suivant les procedures legales appropriees",
                  "Pour proteger nos droits ou la securite de nos utilisateurs en cas de necessite extreme"
                ]
              }
            ]
          },
          {
            title: "7. Securite des donnees",
            content: "Nous mettons en oeuvre des mesures de securite strictes pour proteger vos donnees :",
            items: [
              "Chiffrement des donnees en transit (TLS/SSL)",
              "Regles de securite strictes sur la base de donnees Firestore",
              "Authentification securisee via les protocoles Google Sign-In",
              "Pas de stockage de mots de passe (nous nous appuyons entierement sur l'authentification Google)",
              "Examen periodique des permissions et des acces"
            ]
          },
          {
            title: "8. Vos droits",
            content: "Vous disposez des droits suivants concernant vos donnees :",
            items: [
              "Acces : Vous pouvez demander une copie de vos donnees stockees",
              "Correction : Vous pouvez mettre a jour les informations de votre profil via les parametres de votre compte Google",
              "Suppression : Vous pouvez demander la suppression de votre compte et de toutes les donnees associees",
              "Desabonnement : Vous pouvez desactiver les notifications dans les parametres de l'application",
              "Retrait du consentement : Vous pouvez revoquer les autorisations de connexion dans les parametres de votre compte Google"
            ]
          },
          {
            title: "9. Comment supprimer votre compte et vos donnees",
            content: "Nous offrons a tous les utilisateurs la possibilite de supprimer leurs comptes directement depuis l'application elle-meme, sans avoir besoin de visiter un site externe ou de prendre des mesures supplementaires. Cette fonctionnalite est entierement disponible pour tous les utilisateurs.",
            subsections: [
              {
                title: "Methode principale : Directement depuis l'application (Recommandee)",
                items: [
                  "Ouvrez l'application et allez dans Parametres",
                  "Appuyez sur \"Supprimer le compte\"",
                  "Confirmez votre demande de suppression",
                  "Toutes vos donnees seront supprimees immediatement et definitivement"
                ],
                note: "C'est la methode la plus rapide et la plus simple - vous n'avez besoin de rien d'autre."
              },
              {
                title: "Methode alternative : Par e-mail (si vous ne pouvez pas acceder a l'application)",
                items: [
                  "Envoyez une demande de suppression a : oroekekdkdjjddjjdke@gmail.com",
                  "Incluez votre adresse e-mail associee au compte",
                  "Nous traiterons votre demande dans les 7 jours ouvrables",
                  "Vous recevrez une confirmation lorsque la suppression sera terminee"
                ]
              }
            ],
            note: "Les donnees qui seront supprimees comprennent : informations de profil, jetons FCM, contenu enregistre et toutes les donnees associees a votre compte sur nos serveurs. Les donnees de personnalisation locales sur votre appareil peuvent etre supprimees en desinstallant l'application. Note : Certains signalements que vous avez soumis peuvent rester anonymises (sans lien avec votre compte) pour maintenir l'integrite du contenu."
          },
          {
            title: "10. Confidentialite des enfants",
            content: "Notre application est concue pour un public general. Nous ne collectons pas sciemment d'informations personnelles aupres d'enfants de moins de 13 ans. Si nous apprenons qu'un enfant de moins de 13 ans nous a fourni des informations personnelles, nous les supprimerons immediatement. Si vous etes un parent ou un tuteur et pensez que votre enfant nous a fourni des informations, veuillez nous contacter."
          },
          {
            title: "11. Modifications de la politique de confidentialite",
            content: "Nous pouvons mettre a jour cette politique de temps en temps. Nous vous informerons de tout changement important via :",
            items: [
              "Notification dans l'application",
              "Mise a jour de la date \"Derniere mise a jour\" sur cette page",
              "Notification par e-mail pour les changements significatifs"
            ],
            note: "Votre utilisation continue de l'application apres la publication des modifications signifie que vous acceptez la politique mise a jour."
          }
        ]
      },
      termsOfService: {
        title: "Conditions d'utilisation",
        sections: [
          {
            title: "1. Acceptation des conditions",
            content: "En telechargeant, installant ou utilisant l'application Nibras, vous acceptez d'etre lie par ces Conditions d'utilisation. Si vous n'acceptez pas ces conditions, veuillez ne pas utiliser notre application."
          },
          {
            title: "2. Description du service",
            content: "Nibras est une plateforme de partage de connaissances offrant un acces a du contenu educatif comprenant des livres, des videos et d'autres materiaux lies aux connaissances religieuses de diverses ecoles de pensee islamiques, ainsi qu'aux sciences mondaines. L'application est disponible en trois langues : arabe, anglais et francais."
          },
          {
            title: "3. Comptes utilisateurs",
            content: "La connexion a l'application Nibras est facultative et non obligatoire. Vous pouvez utiliser l'application en tant qu'invite sans creer de compte. Si vous choisissez de vous connecter avec votre compte Google, vous acceptez de :",
            items: [
              "Fournir des informations exactes et completes",
              "Maintenir la securite des identifiants de votre compte",
              "Etre responsable de toutes les activites qui se produisent sous votre compte",
              "Nous informer immediatement de toute utilisation non autorisee de votre compte"
            ],
            note: "Note : Certaines fonctionnalites telles que l'enregistrement du contenu et la personnalisation peuvent necessiter une connexion."
          },
          {
            title: "4. Utilisation acceptable",
            content: "Vous acceptez d'utiliser Nibras uniquement a des fins legales et conformement a ces conditions. Vous acceptez de ne pas :",
            items: [
              "Utiliser l'application d'une maniere qui viole les lois ou reglementations applicables",
              "Tenter un acces non autorise a toute partie de l'application",
              "Interferer avec ou perturber l'integrite ou les performances de l'application",
              "Copier, modifier, distribuer ou creer des oeuvres derivees de notre contenu sans autorisation",
              "Utiliser des systemes ou logiciels automatises pour extraire des donnees de l'application"
            ]
          },
          {
            title: "5. Propriete intellectuelle",
            content: "Le contenu disponible via Nibras, y compris mais sans s'y limiter le texte, les graphiques, les logos, les images et le contenu audio/video, est protege par les lois sur le droit d'auteur, les marques de commerce et d'autres lois sur la propriete intellectuelle. Le contenu est fourni uniquement pour un usage educatif personnel et non commercial."
          },
          {
            title: "6. Avertissement sur le contenu",
            content: "Nibras fournit du contenu provenant de diverses ecoles de pensee islamiques et de sciences mondaines a des fins educatives. La presence de tout contenu ne constitue pas une approbation d'un point de vue particulier. Nous encourageons les utilisateurs a aborder tout le contenu avec un esprit critique et a consulter des savants qualifies pour des conseils religieux."
          },
          {
            title: "7. Disponibilite et mises a jour",
            content: "Nous nous efforcons de maintenir la disponibilite de Nibras a tout moment, mais nous ne garantissons pas un acces ininterrompu a nos services. Nous pouvons modifier, suspendre ou interrompre toute partie de l'application a tout moment sans preavis."
          },
          {
            title: "8. Limitation de responsabilite",
            content: "Dans toute la mesure permise par la loi, Nibras et ses developpeurs ne seront pas responsables des dommages indirects, accessoires, speciaux, consecutifs ou punitifs, y compris mais sans s'y limiter la perte de profits, de donnees ou d'autres pertes intangibles."
          },
          {
            title: "9. Indemnisation",
            content: "Vous acceptez d'indemniser, de defendre et de degager de toute responsabilite Nibras, ses developpeurs, dirigeants et employes de toute reclamation, dommage, responsabilite ou cout decoulant de votre utilisation de l'application ou de votre violation de ces conditions."
          },
          {
            title: "10. Modifications des conditions",
            content: "Nous nous reservons le droit de modifier ces conditions a tout moment. Les modifications seront publiees sur cette page avec une date \"Derniere mise a jour\" mise a jour. Votre utilisation continue de l'application apres les modifications constitue une acceptation des conditions modifiees."
          }
        ]
      },
      contact: {
        title: "11. Nous contacter",
        content: "Si vous avez des questions ou des preoccupations concernant cette Politique de confidentialite ou ces Conditions d'utilisation, veuillez nous contacter par e-mail :"
      }
    }
  }

  const c = content[locale]
  const dateLocale = locale === 'ar' ? 'ar-SA' : locale === 'fr' ? 'fr-FR' : 'en-US'
  
  return (
    <div className="pt-24 pb-16 bg-background">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        <header className="text-center mb-12">
          <h1 className="text-4xl sm:text-5xl font-serif font-bold text-foreground mb-4">
            {c.title}
          </h1>
          <p className="text-muted-foreground">
            {c.lastUpdated}: {new Date().toLocaleDateString(dateLocale, { month: 'long', day: 'numeric', year: 'numeric' })}
          </p>
        </header>

        <div className="prose prose-lg max-w-none">
          {/* Privacy Policy Section */}
          <section className="mb-16">
            <h2 className="text-3xl font-serif font-bold text-foreground mb-6 pb-2 border-b border-border">
              {c.privacyPolicy.title}
            </h2>
            
            <div className="space-y-8">
              {c.privacyPolicy.sections.map((section, index) => (
                <div key={index}>
                  <h3 className="text-xl font-serif font-semibold text-foreground mb-3">
                    {section.title}
                  </h3>
                  <p className="text-muted-foreground leading-relaxed mb-4">
                    {section.content}
                  </p>
                  
                  {section.subsections && section.subsections.map((sub, subIndex) => (
                    <div key={subIndex} className="bg-secondary rounded-lg p-4 border border-border mb-4">
                      <h4 className="font-semibold text-foreground mb-2">{sub.title}</h4>
                      <ul className="space-y-1 text-sm text-muted-foreground mb-2">
                        {sub.items.map((item, itemIndex) => (
                          <li key={itemIndex} className="flex items-start gap-2">
                            <span className="text-primary mt-1">•</span>
                            <span>{item}</span>
                          </li>
                        ))}
                      </ul>
                      {sub.purpose && (
                        <p className="text-sm text-primary font-medium mt-2">{sub.purpose}</p>
                      )}
                      {sub.note && (
                        <p className="text-sm text-accent font-medium mt-2 bg-accent/10 p-2 rounded">{sub.note}</p>
                      )}
                    </div>
                  ))}
                  
                  {section.items && (
                    <ul className="space-y-2 text-muted-foreground">
                      {section.items.map((item, itemIndex) => (
                        <li key={itemIndex} className="flex items-start gap-2">
                          <span className="text-primary mt-1">•</span>
                          <span>{item}</span>
                        </li>
                      ))}
                    </ul>
                  )}
                  
                  {section.note && (
                    <p className="text-sm text-accent font-medium mt-4 bg-accent/10 p-3 rounded-lg border border-accent/20">
                      {section.note}
                    </p>
                  )}
                </div>
              ))}
            </div>
          </section>

          {/* Terms of Service Section */}
          <section id="terms" className="scroll-mt-24">
            <h2 className="text-3xl font-serif font-bold text-foreground mb-6 pb-2 border-b border-border">
              {c.termsOfService.title}
            </h2>
            
            <div className="space-y-8">
              {c.termsOfService.sections.map((section, index) => (
                <div key={index}>
                  <h3 className="text-xl font-serif font-semibold text-foreground mb-3">
                    {section.title}
                  </h3>
                  <p className="text-muted-foreground leading-relaxed mb-4">
                    {section.content}
                  </p>
                  
                  {section.items && (
                    <ul className="space-y-2 text-muted-foreground">
                      {section.items.map((item, itemIndex) => (
                        <li key={itemIndex} className="flex items-start gap-2">
                          <span className="text-primary mt-1">•</span>
                          <span>{item}</span>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              ))}

              {/* Contact Section */}
              <div>
                <h3 className="text-xl font-serif font-semibold text-foreground mb-3">
                  {c.contact.title}
                </h3>
                <p className="text-muted-foreground leading-relaxed">
                  {c.contact.content}
                </p>
                <a 
                  href="mailto:oroekekdkdjjddjjdke@gmail.com" 
                  className="inline-block mt-2 text-primary hover:text-primary/80 transition-colors font-medium"
                  dir="ltr"
                >
                  oroekekdkdjjddjjdke@gmail.com
                </a>
              </div>
            </div>
          </section>
        </div>
      </div>
    </div>
  )
}

export default function PrivacyPage() {
  return (
    <LocaleProvider>
      <main className="min-h-screen">
        <Navbar />
        <PrivacyContent />
        <Footer />
      </main>
    </LocaleProvider>
  )
}
