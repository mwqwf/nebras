import { Metadata } from "next"

export const metadata: Metadata = {
  title: "سياسة الخصوصية وشروط الاستخدام - نِبراس | Privacy Policy - Nibras",
  description: "اقرأ سياسة الخصوصية وشروط الاستخدام لتطبيق نِبراس. تعرف على كيفية حماية بياناتك والتزامنا بخصوصيتك. | Read Nibras Privacy Policy and Terms of Service. Learn how we protect your data and our commitment to your privacy.",
}

export default function PrivacyLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return children
}
