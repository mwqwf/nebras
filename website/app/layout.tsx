import type { Metadata } from 'next'
import { Noto_Naskh_Arabic, Tajawal } from 'next/font/google'
import { Analytics } from '@vercel/analytics/next'
import './globals.css'

const notoNaskhArabic = Noto_Naskh_Arabic({ 
  subsets: ['arabic'],
  variable: '--font-naskh',
  display: 'swap',
  weight: ['400', '500', '600', '700'],
})

const tajawal = Tajawal({ 
  subsets: ['arabic'],
  variable: '--font-tajawal',
  display: 'swap',
  weight: ['300', '400', '500', '700', '800'],
})

export const metadata: Metadata = {
  title: 'نِبراس - بوابتك إلى عالم المعرفة | Nibras - Your Gateway to Knowledge',
  description: 'نِبراس هو أرشيف علمي ناشئ ومتنامٍ باستمرار، يُعنى بجمع المعارف الدينية والدنيوية من مختلف المذاهب الإسلامية والعلوم الطبيعية وغيرها. التطبيق متوفر بثلاث لغات: العربية والإنجليزية والفرنسية. | Nibras is an emerging and constantly growing scientific archive. Available in three languages: Arabic, English, and French.',
  keywords: ['نبراس', 'Nibras', 'كتب إسلامية', 'Islamic books', 'أرشيف علمي', 'scientific archive', 'المذاهب الإسلامية', 'Islamic schools', 'فيديوهات تعليمية', 'educational videos', 'العلوم الطبيعية', 'natural sciences', 'تطبيق إسلامي', 'Islamic app', 'Arabic', 'English', 'French', 'multilingual'],
  openGraph: {
    title: 'نِبراس - بوابتك إلى عالم المعرفة | Nibras - Your Gateway to Knowledge',
    description: 'استكشف مجموعة واسعة من المعارف الدينية والدنيوية من خلال الكتب والفيديوهات. متوفر بثلاث لغات: العربية والإنجليزية والفرنسية. | Explore a wide range of religious and worldly knowledge. Available in Arabic, English, and French.',
    type: 'website',
  },
}

export const viewport = {
  themeColor: '#1a5f4a',
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="ar" dir="rtl" className={`${notoNaskhArabic.variable} ${tajawal.variable} bg-background`}>
      <body className="font-sans antialiased">
        {children}
        {process.env.NODE_ENV === 'production' && <Analytics />}
      </body>
    </html>
  )
}
