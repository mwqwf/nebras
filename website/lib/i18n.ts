export type Locale = 'ar' | 'en' | 'fr'

export const locales: Locale[] = ['ar', 'en', 'fr']

export const localeNames: Record<Locale, string> = {
  ar: 'العربية',
  en: 'English',
  fr: 'Francais'
}

export const localeDirections: Record<Locale, 'rtl' | 'ltr'> = {
  ar: 'rtl',
  en: 'ltr',
  fr: 'ltr'
}

export const translations = {
  ar: {
    // Navbar
    nav: {
      home: 'الرئيسية',
      features: 'المميزات',
      about: 'عن التطبيق',
      privacy: 'الخصوصية',
      download: 'حمّل التطبيق',
      openMenu: 'فتح القائمة'
    },
    // Hero Section
    hero: {
      greeting: 'السَّلامُ عَلَيْكُمْ وَرَحْمَةُ اللهِ وَبَرَكَاتُه',
      welcome: 'أهلاً وسهلاً بكم في تطبيق نِبراس',
      badge: 'إطلاق جديد - أرشيف متنامٍ باستمرار',
      title: 'اكتشف نور',
      titleHighlight: 'المعرفة',
      description: 'هو أرشيف علمي',
      descriptionHighlight: 'ناشئ ومتنامٍ باستمرار',
      descriptionContinue: '، يُعنى بجمع المعارف الدينية والدنيوية من مختلف المذاهب الإسلامية والعلوم الطبيعية وغيرها.',
      subDescription: 'ليس مجرد كتب فحسب! بل فيديوهات تعليمية ومحتوى متنوع يُضاف إليه باستمرار، مع تجربة مخصصة تتكيف مع اهتماماتك.',
      downloadBtn: 'حمّل من Google Play',
      exploreBtn: 'اكتشف المميزات',
      languages: 'متوفر بثلاث لغات: العربية والإنجليزية والفرنسية',
      highlights: {
        books: { label: 'كتب متنوعة', desc: 'أرشيف متنامٍ' },
        videos: { label: 'فيديوهات تعليمية', desc: 'محتوى مرئي' },
        schools: { label: 'مذاهب متعددة', desc: 'تنوع فكري' },
        personalized: { label: 'تجربة مخصصة', desc: 'حسب اهتماماتك' }
      }
    },
    // Features Section
    features: {
      badge: 'مميزات التطبيق',
      title: 'كل ما تحتاجه للتعلم',
      subtitle: 'نِبراس يجمع لك أفضل ما في التراث العلمي والمعرفة الحديثة في منصة واحدة جميلة وسهلة الاستخدام.',
      items: [
        {
          title: 'أرشيف علمي شامل',
          description: 'مجموعة واسعة من الكتب تشمل النصوص الدينية والفقه والعقيدة والفلسفة والعلوم الطبيعية من مختلف المذاهب والمدارس الفكرية.'
        },
        {
          title: 'فيديوهات تعليمية',
          description: 'نِبراس ليس مجرد كتب! استمتع بمحتوى مرئي متنوع يشمل محاضرات ودروس ونقاشات من علماء ومفكرين بارزين.'
        },
        {
          title: 'تجربة مخصصة لك',
          description: 'سجّل الدخول بحساب Google الخاص بك لتجربة تعلّم مخصصة. يتعرف التطبيق على اهتماماتك من خلال الكتب التي تتصفحها والفيديوهات التي تشاهدها.'
        },
        {
          title: 'تعدد المذاهب والمدارس',
          description: 'احتضان لثراء المعرفة الإسلامية من مختلف المذاهب الفقهية والمدارس الفكرية، مع تقديمها بموضوعية واحترام.'
        },
        {
          title: 'العلوم الدنيوية',
          description: 'بالإضافة إلى المعارف الدينية، اكتشف محتوى في العلوم الطبيعية والرياضيات والفلك والطب وغيرها من المجالات التي أثرت الحضارة الإسلامية.'
        },
        {
          title: 'محتوى متنامٍ باستمرار',
          description: 'أرشيفنا في نمو مستمر! كتب وفيديوهات ومصادر جديدة تُضاف بانتظام. عُد دائماً لاكتشاف المزيد من المحتوى الذي يُعمّق فهمك.'
        }
      ]
    },
    // Personalization Section
    personalization: {
      badge: 'تجربة شخصية',
      title: 'رفيقك الشخصي',
      titleHighlight: 'في رحلة التعلم',
      description: 'مثل YouTube والمنصات الحديثة الأخرى، يُنشئ نِبراس تجربة مخصصة تتكيف مع اهتماماتك الفريدة ورحلتك في طلب العلم.',
      steps: [
        'سجّل الدخول بسهولة عبر حساب Google الخاص بك',
        'تصفّح الكتب وشاهد الفيديوهات التي تهمك',
        'احصل على توصيات مخصصة بناءً على نشاطك',
        'ابنِ مكتبتك الخاصة من المحتوى المحفوظ',
        'تابع تقدمك في رحلة التعلم'
      ],
      privacyNote: 'نستخدم تسجيل الدخول عبر Google للمصادقة فقط. نشاطك داخل التطبيق يساعد في تخصيص تجربتك، لكننا',
      privacyHighlight: 'لا نجمع أو نبيع بياناتك الشخصية',
      privacyFirst: 'خصوصيتك أولاً:',
      recommendedFor: 'مُوصى به لك',
      basedOnInterests: 'بناءً على اهتماماتك',
      newContent: 'محتوى جديد',
      addedDaily: 'يُضاف يومياً',
      recommendations: 'توصيات',
      personalizedForYou: 'مُخصصة لك',
      tags: ['فقه', 'حديث', 'علوم', 'تاريخ', 'عقيدة', 'فلسفة']
    },
    // About Section
    about: {
      title: 'ما معنى نِبراس؟',
      description: 'كلمة عربية تعني',
      lamp: 'المصباح',
      or: 'أو',
      light: 'النور',
      descriptionContinue: '. وكما يُنير المصباح الظلام، يهدف تطبيقنا إلى إنارة العقول بنور المعرفة، وإرشاد طالبي العلم عبر بحر الحكمة الدينية والدنيوية الواسع.',
      pillars: [
        { title: 'نُنير', description: 'نُسلط الضوء على المواضيع المعقدة من خلال محتوى منتقى بعناية' },
        { title: 'نُرشد', description: 'نُساعدك على التنقل في عالم المعرفة الإسلامية والدنيوية الواسع' },
        { title: 'نُلهم', description: 'نُشعل شرارة الفضول وحب التعلم مدى الحياة' }
      ]
    },
    // Growth Section
    growth: {
      badge: 'تطبيق ناشئ',
      title: 'أرشيف في نمو مستمر',
      subtitle: 'نِبراس في مراحله الأولى ويتطور باستمرار. انضم إلينا في هذه الرحلة وكن جزءاً من مجتمع طالبي العلم.',
      cards: [
        { title: 'محتوى متزايد', description: 'كتب وفيديوهات جديدة تُضاف بانتظام إلى الأرشيف' },
        { title: 'تحديثات مستمرة', description: 'مميزات جديدة وتحسينات دورية لتجربة أفضل' },
        { title: 'جودة عالية', description: 'محتوى منتقى بعناية من مصادر موثوقة ومعتمدة' }
      ]
    },
    // CTA Section
    cta: {
      title: 'ابدأ رحلتك اليوم',
      description: 'انضم إلى طالبي العلم الذين اكتشفوا نور المعرفة عبر نِبراس. حمّل التطبيق الآن وابدأ الاستكشاف.',
      downloadBtn: 'حمّل من Google Play'
    },
    // Footer
    footer: {
      tagline: 'نُنير العقول بنور العلم والمعرفة من خلال تراث العلماء والمفكرين. رحلتك نحو المعرفة تبدأ من هنا.',
      quickLinks: 'روابط سريعة',
      legal: 'قانوني',
      contact: 'تواصل معنا',
      privacyPolicy: 'سياسة الخصوصية',
      terms: 'شروط الاستخدام',
      copyright: 'جميع الحقوق محفوظة'
    }
  },
  en: {
    // Navbar
    nav: {
      home: 'Home',
      features: 'Features',
      about: 'About',
      privacy: 'Privacy',
      download: 'Download App',
      openMenu: 'Open menu'
    },
    // Hero Section
    hero: {
      greeting: 'Peace be upon you and the mercy and blessings of God',
      welcome: 'Welcome to Nibras application',
      badge: 'New Launch - Continuously Growing Archive',
      title: 'Discover the Light of',
      titleHighlight: 'Knowledge',
      description: 'is a scientific archive',
      descriptionHighlight: 'emerging and constantly growing',
      descriptionContinue: ', dedicated to collecting religious and worldly knowledge from various Islamic schools of thought, natural sciences, and more.',
      subDescription: 'Not just books! Educational videos and diverse content are constantly being added, with a personalized experience that adapts to your interests.',
      downloadBtn: 'Download from Google Play',
      exploreBtn: 'Explore Features',
      languages: 'Available in three languages: Arabic, English, and French',
      highlights: {
        books: { label: 'Diverse Books', desc: 'Growing archive' },
        videos: { label: 'Educational Videos', desc: 'Visual content' },
        schools: { label: 'Multiple Schools', desc: 'Intellectual diversity' },
        personalized: { label: 'Personalized', desc: 'Based on your interests' }
      }
    },
    // Features Section
    features: {
      badge: 'App Features',
      title: 'Everything You Need to Learn',
      subtitle: 'Nibras brings you the best of scientific heritage and modern knowledge in one beautiful and easy-to-use platform.',
      items: [
        {
          title: 'Comprehensive Scientific Archive',
          description: 'A wide collection of books covering religious texts, jurisprudence, theology, philosophy, and natural sciences from various schools of thought.'
        },
        {
          title: 'Educational Videos',
          description: 'Nibras is not just books! Enjoy diverse visual content including lectures, lessons, and discussions from prominent scholars and thinkers.'
        },
        {
          title: 'Personalized Experience',
          description: 'Sign in with your Google account for a customized learning experience. The app learns your interests through the books you browse and videos you watch.'
        },
        {
          title: 'Multiple Schools of Thought',
          description: 'Embracing the richness of Islamic knowledge from various jurisprudential schools and intellectual traditions, presented objectively and respectfully.'
        },
        {
          title: 'Worldly Sciences',
          description: 'In addition to religious knowledge, discover content in natural sciences, mathematics, astronomy, medicine, and other fields that enriched Islamic civilization.'
        },
        {
          title: 'Constantly Growing Content',
          description: 'Our archive is continuously growing! New books, videos, and resources are added regularly. Keep coming back to discover more content that deepens your understanding.'
        }
      ]
    },
    // Personalization Section
    personalization: {
      badge: 'Personal Experience',
      title: 'Your Personal Companion',
      titleHighlight: 'on the Learning Journey',
      description: 'Like YouTube and other modern platforms, Nibras creates a personalized experience that adapts to your unique interests and journey in seeking knowledge.',
      steps: [
        'Sign in easily with your Google account',
        'Browse books and watch videos that interest you',
        'Get personalized recommendations based on your activity',
        'Build your own library of saved content',
        'Track your progress on your learning journey'
      ],
      privacyNote: 'We use Google Sign-In for authentication only. Your in-app activity helps personalize your experience, but we',
      privacyHighlight: 'do not collect or sell your personal data',
      privacyFirst: 'Your Privacy First:',
      recommendedFor: 'Recommended for You',
      basedOnInterests: 'Based on your interests',
      newContent: 'New Content',
      addedDaily: 'Added daily',
      recommendations: 'Recommendations',
      personalizedForYou: 'Personalized for you',
      tags: ['Jurisprudence', 'Hadith', 'Sciences', 'History', 'Theology', 'Philosophy']
    },
    // About Section
    about: {
      title: 'What Does Nibras Mean?',
      description: 'is an Arabic word meaning',
      lamp: 'The Lamp',
      or: 'or',
      light: 'The Light',
      descriptionContinue: '. Just as a lamp illuminates darkness, our application aims to enlighten minds with the light of knowledge, guiding seekers of knowledge through the vast ocean of religious and worldly wisdom.',
      pillars: [
        { title: 'We Illuminate', description: 'We shed light on complex topics through carefully curated content' },
        { title: 'We Guide', description: 'We help you navigate the vast world of Islamic and worldly knowledge' },
        { title: 'We Inspire', description: 'We ignite the spark of curiosity and lifelong love of learning' }
      ]
    },
    // Growth Section
    growth: {
      badge: 'Emerging App',
      title: 'An Archive in Continuous Growth',
      subtitle: 'Nibras is in its early stages and constantly evolving. Join us on this journey and be part of the community of knowledge seekers.',
      cards: [
        { title: 'Growing Content', description: 'New books and videos are regularly added to the archive' },
        { title: 'Continuous Updates', description: 'New features and periodic improvements for a better experience' },
        { title: 'High Quality', description: 'Content carefully selected from reliable and trusted sources' }
      ]
    },
    // CTA Section
    cta: {
      title: 'Start Your Journey Today',
      description: 'Join the knowledge seekers who have discovered the light of knowledge through Nibras. Download the app now and start exploring.',
      downloadBtn: 'Download from Google Play'
    },
    // Footer
    footer: {
      tagline: 'We illuminate minds with the light of knowledge through the heritage of scholars and thinkers. Your journey to knowledge starts here.',
      quickLinks: 'Quick Links',
      legal: 'Legal',
      contact: 'Contact Us',
      privacyPolicy: 'Privacy Policy',
      terms: 'Terms of Service',
      copyright: 'All rights reserved'
    }
  },
  fr: {
    // Navbar
    nav: {
      home: 'Accueil',
      features: 'Fonctionnalites',
      about: 'A propos',
      privacy: 'Confidentialite',
      download: 'Telecharger',
      openMenu: 'Ouvrir le menu'
    },
    // Hero Section
    hero: {
      greeting: 'Que la paix, la misericorde et les benedictions de Dieu soient sur vous',
      welcome: 'Bienvenue dans l\'application Nibras',
      badge: 'Nouveau lancement - Archive en croissance continue',
      title: 'Decouvrez la Lumiere de la',
      titleHighlight: 'Connaissance',
      description: 'est une archive scientifique',
      descriptionHighlight: 'emergente et en croissance constante',
      descriptionContinue: ', dediee a la collecte des connaissances religieuses et mondaines de diverses ecoles de pensee islamiques, des sciences naturelles et plus encore.',
      subDescription: 'Pas seulement des livres ! Des videos educatives et du contenu diversifie sont constamment ajoutes, avec une experience personnalisee qui s\'adapte a vos interets.',
      downloadBtn: 'Telecharger depuis Google Play',
      exploreBtn: 'Decouvrir les fonctionnalites',
      languages: 'Disponible en trois langues : arabe, anglais et francais',
      highlights: {
        books: { label: 'Livres divers', desc: 'Archive croissante' },
        videos: { label: 'Videos educatives', desc: 'Contenu visuel' },
        schools: { label: 'Plusieurs ecoles', desc: 'Diversite intellectuelle' },
        personalized: { label: 'Personnalise', desc: 'Selon vos interets' }
      }
    },
    // Features Section
    features: {
      badge: 'Fonctionnalites de l\'app',
      title: 'Tout ce dont vous avez besoin pour apprendre',
      subtitle: 'Nibras vous apporte le meilleur du patrimoine scientifique et des connaissances modernes dans une plateforme belle et facile a utiliser.',
      items: [
        {
          title: 'Archive scientifique complete',
          description: 'Une vaste collection de livres couvrant les textes religieux, la jurisprudence, la theologie, la philosophie et les sciences naturelles de diverses ecoles de pensee.'
        },
        {
          title: 'Videos educatives',
          description: 'Nibras n\'est pas que des livres ! Profitez d\'un contenu visuel diversifie comprenant des conferences, des lecons et des discussions de savants et penseurs eminents.'
        },
        {
          title: 'Experience personnalisee',
          description: 'Connectez-vous avec votre compte Google pour une experience d\'apprentissage personnalisee. L\'application apprend vos interets a travers les livres que vous parcourez et les videos que vous regardez.'
        },
        {
          title: 'Plusieurs ecoles de pensee',
          description: 'Embrasser la richesse de la connaissance islamique de diverses ecoles juridiques et traditions intellectuelles, presentees objectivement et respectueusement.'
        },
        {
          title: 'Sciences mondaines',
          description: 'En plus des connaissances religieuses, decouvrez du contenu en sciences naturelles, mathematiques, astronomie, medecine et d\'autres domaines qui ont enrichi la civilisation islamique.'
        },
        {
          title: 'Contenu en croissance constante',
          description: 'Notre archive est en croissance continue ! De nouveaux livres, videos et ressources sont ajoutes regulierement. Revenez pour decouvrir plus de contenu qui approfondit votre comprehension.'
        }
      ]
    },
    // Personalization Section
    personalization: {
      badge: 'Experience personnelle',
      title: 'Votre compagnon personnel',
      titleHighlight: 'dans le voyage d\'apprentissage',
      description: 'Comme YouTube et d\'autres plateformes modernes, Nibras cree une experience personnalisee qui s\'adapte a vos interets uniques et a votre parcours dans la quete du savoir.',
      steps: [
        'Connectez-vous facilement avec votre compte Google',
        'Parcourez les livres et regardez les videos qui vous interessent',
        'Obtenez des recommandations personnalisees basees sur votre activite',
        'Construisez votre propre bibliotheque de contenu sauvegarde',
        'Suivez votre progression dans votre parcours d\'apprentissage'
      ],
      privacyNote: 'Nous utilisons la connexion Google uniquement pour l\'authentification. Votre activite dans l\'application aide a personnaliser votre experience, mais nous',
      privacyHighlight: 'ne collectons ni ne vendons vos donnees personnelles',
      privacyFirst: 'Votre vie privee d\'abord :',
      recommendedFor: 'Recommande pour vous',
      basedOnInterests: 'Base sur vos interets',
      newContent: 'Nouveau contenu',
      addedDaily: 'Ajoute quotidiennement',
      recommendations: 'Recommandations',
      personalizedForYou: 'Personnalise pour vous',
      tags: ['Jurisprudence', 'Hadith', 'Sciences', 'Histoire', 'Theologie', 'Philosophie']
    },
    // About Section
    about: {
      title: 'Que signifie Nibras ?',
      description: 'est un mot arabe signifiant',
      lamp: 'La Lampe',
      or: 'ou',
      light: 'La Lumiere',
      descriptionContinue: '. Tout comme une lampe illumine les tenebres, notre application vise a eclairer les esprits avec la lumiere de la connaissance, guidant les chercheurs de savoir a travers le vaste ocean de la sagesse religieuse et mondaine.',
      pillars: [
        { title: 'Nous illuminons', description: 'Nous eclairons les sujets complexes a travers un contenu soigneusement selectionne' },
        { title: 'Nous guidons', description: 'Nous vous aidons a naviguer dans le vaste monde de la connaissance islamique et mondaine' },
        { title: 'Nous inspirons', description: 'Nous allumons l\'etincelle de la curiosite et l\'amour de l\'apprentissage tout au long de la vie' }
      ]
    },
    // Growth Section
    growth: {
      badge: 'Application emergente',
      title: 'Une archive en croissance continue',
      subtitle: 'Nibras est a ses debuts et evolue constamment. Rejoignez-nous dans ce voyage et faites partie de la communaute des chercheurs de connaissance.',
      cards: [
        { title: 'Contenu croissant', description: 'De nouveaux livres et videos sont regulierement ajoutes a l\'archive' },
        { title: 'Mises a jour continues', description: 'Nouvelles fonctionnalites et ameliorations periodiques pour une meilleure experience' },
        { title: 'Haute qualite', description: 'Contenu soigneusement selectionne a partir de sources fiables et de confiance' }
      ]
    },
    // CTA Section
    cta: {
      title: 'Commencez votre voyage aujourd\'hui',
      description: 'Rejoignez les chercheurs de connaissance qui ont decouvert la lumiere du savoir a travers Nibras. Telechargez l\'application maintenant et commencez a explorer.',
      downloadBtn: 'Telecharger depuis Google Play'
    },
    // Footer
    footer: {
      tagline: 'Nous illuminons les esprits avec la lumiere de la connaissance a travers le patrimoine des savants et des penseurs. Votre voyage vers la connaissance commence ici.',
      quickLinks: 'Liens rapides',
      legal: 'Legal',
      contact: 'Contactez-nous',
      privacyPolicy: 'Politique de confidentialite',
      terms: 'Conditions d\'utilisation',
      copyright: 'Tous droits reserves'
    }
  }
}

export function getTranslation(locale: Locale) {
  return translations[locale]
}
