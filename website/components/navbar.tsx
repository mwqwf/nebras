"use client"

import Link from "next/link"
import { useState } from "react"
import { Menu, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { LanguageSwitcher } from "@/components/language-switcher"
import { useLocale } from "@/components/locale-provider"

export function Navbar() {
  const [isOpen, setIsOpen] = useState(false)
  const { locale, setLocale, t } = useLocale()

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 bg-background/80 backdrop-blur-md border-b border-border">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <Link href="/" className="flex items-center gap-3">
            <div className="w-11 h-11 rounded-full bg-primary flex items-center justify-center shadow-lg">
              <span className="text-primary-foreground font-serif text-xl font-bold">ن</span>
            </div>
            <span className="text-2xl font-serif font-bold text-foreground">نِبراس</span>
          </Link>
          
          <div className="hidden md:flex items-center gap-6">
            <Link href="/" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors">
              {t.nav.home}
            </Link>
            <Link href="#features" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors">
              {t.nav.features}
            </Link>
            <Link href="#about" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors">
              {t.nav.about}
            </Link>
            <Link href="/privacy" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors">
              {t.nav.privacy}
            </Link>
            <LanguageSwitcher currentLocale={locale} onLocaleChange={setLocale} />
            <Button asChild>
              <a href="https://play.google.com/store" target="_blank" rel="noopener noreferrer">
                {t.nav.download}
              </a>
            </Button>
          </div>

          <div className="flex items-center gap-2 md:hidden">
            <LanguageSwitcher currentLocale={locale} onLocaleChange={setLocale} />
            <button
              className="p-2"
              onClick={() => setIsOpen(!isOpen)}
              aria-label={t.nav.openMenu}
            >
              {isOpen ? <X className="h-6 w-6" /> : <Menu className="h-6 w-6" />}
            </button>
          </div>
        </div>
      </div>

      {isOpen && (
        <div className="md:hidden bg-background border-b border-border">
          <div className="px-4 py-4 space-y-3">
            <Link href="/" className="block text-sm font-medium text-muted-foreground hover:text-foreground transition-colors" onClick={() => setIsOpen(false)}>
              {t.nav.home}
            </Link>
            <Link href="#features" className="block text-sm font-medium text-muted-foreground hover:text-foreground transition-colors" onClick={() => setIsOpen(false)}>
              {t.nav.features}
            </Link>
            <Link href="#about" className="block text-sm font-medium text-muted-foreground hover:text-foreground transition-colors" onClick={() => setIsOpen(false)}>
              {t.nav.about}
            </Link>
            <Link href="/privacy" className="block text-sm font-medium text-muted-foreground hover:text-foreground transition-colors" onClick={() => setIsOpen(false)}>
              {t.nav.privacy}
            </Link>
            <Button asChild className="w-full">
              <a href="https://play.google.com/store" target="_blank" rel="noopener noreferrer">
                {t.nav.download}
              </a>
            </Button>
          </div>
        </div>
      )}
    </nav>
  )
}
