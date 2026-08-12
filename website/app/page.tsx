"use client"

import { Navbar } from "@/components/navbar"
import { Footer } from "@/components/footer"
import { LocaleProvider } from "@/components/locale-provider"
import { 
  HeroSection, 
  FeaturesSection, 
  PersonalizationSection, 
  AboutSection, 
  GrowthSection,
  CTASection 
} from "@/components/home-sections"

export default function HomePage() {
  return (
    <LocaleProvider>
      <main className="min-h-screen">
        <Navbar />
        <HeroSection />
        <FeaturesSection />
        <PersonalizationSection />
        <GrowthSection />
        <AboutSection />
        <CTASection />
        <Footer />
      </main>
    </LocaleProvider>
  )
}
