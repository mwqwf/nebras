"use client"

import { BookOpen, Video, User, Sparkles, Library, Globe, Lightbulb, TrendingUp, Rocket, Star } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { useLocale } from "@/components/locale-provider"

export function HeroSection() {
  const { t } = useLocale()
  
  const highlights = [
    { icon: BookOpen, ...t.hero.highlights.books },
    { icon: Video, ...t.hero.highlights.videos },
    { icon: Globe, ...t.hero.highlights.schools },
    { icon: User, ...t.hero.highlights.personalized },
  ]

  return (
    <section className="relative min-h-screen flex items-center justify-center pt-16 overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-primary/10 via-background to-background" />
      
      {/* Decorative elements */}
      <div className="absolute top-32 right-10 w-72 h-72 bg-primary/5 rounded-full blur-3xl" />
      <div className="absolute bottom-32 left-10 w-96 h-96 bg-accent/5 rounded-full blur-3xl" />
      
      <div className="relative z-10 max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20 text-center">
        {/* Islamic Greeting */}
        <div className="mb-8">
          <p className="text-2xl sm:text-3xl font-serif text-primary mb-2">
            {t.hero.greeting}
          </p>
          <p className="text-lg text-muted-foreground">
            {t.hero.welcome}
          </p>
        </div>
        
        {/* Launch Badge */}
        <div className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-primary/10 border border-primary/20 mb-8">
          <Rocket className="h-5 w-5 text-primary" />
          <span className="text-sm font-medium text-primary">{t.hero.badge}</span>
          <Star className="h-4 w-4 text-accent fill-accent" />
        </div>
        
        <h1 className="text-4xl sm:text-5xl lg:text-7xl font-serif font-bold text-foreground leading-tight mb-6 text-balance">
          {t.hero.title}
          <span className="block text-primary mt-2">{t.hero.titleHighlight}</span>
        </h1>
        
        <p className="text-lg sm:text-xl text-muted-foreground max-w-4xl mx-auto leading-relaxed mb-4 text-pretty">
          <strong className="text-foreground">نِبراس</strong> {t.hero.description} <span className="text-primary font-semibold">{t.hero.descriptionHighlight}</span>{t.hero.descriptionContinue}
        </p>
        
        <p className="text-base text-muted-foreground max-w-3xl mx-auto leading-relaxed mb-6">
          {t.hero.subDescription}
        </p>

        {/* Available Languages Badge */}
        <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-accent/10 border border-accent/20 mb-10">
          <Globe className="h-4 w-4 text-accent" />
          <span className="text-sm font-medium text-accent">{t.hero.languages}</span>
        </div>
        
        <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-16">
          <Button size="lg" className="px-8 py-6 text-lg" asChild>
            <a href="https://play.google.com/store" target="_blank" rel="noopener noreferrer">
              {t.hero.downloadBtn}
            </a>
          </Button>
          <Button variant="outline" size="lg" className="px-8 py-6 text-lg" asChild>
            <a href="#features">
              {t.hero.exploreBtn}
            </a>
          </Button>
        </div>
        
        {/* Key highlights without numbers */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 max-w-4xl mx-auto">
          {highlights.map((item, index) => (
            <Card key={index} className="bg-card/50 backdrop-blur-sm border-border hover:border-primary/30 transition-colors">
              <CardContent className="p-4 text-center">
                <item.icon className="h-8 w-8 text-primary mx-auto mb-3" />
                <div className="text-base font-semibold text-foreground mb-1">{item.label}</div>
                <div className="text-xs text-muted-foreground">{item.desc}</div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </section>
  )
}

export function FeaturesSection() {
  const { t } = useLocale()
  
  const icons = [Library, Video, User, Globe, Lightbulb, TrendingUp]
  const features = t.features.items.map((item, index) => ({
    icon: icons[index],
    ...item
  }))

  return (
    <section id="features" className="py-20 bg-secondary">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-16">
          <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 border border-primary/20 mb-6">
            <Sparkles className="h-4 w-4 text-primary" />
            <span className="text-sm font-medium text-primary">{t.features.badge}</span>
          </div>
          <h2 className="text-3xl sm:text-4xl lg:text-5xl font-serif font-bold text-foreground mb-4">
            {t.features.title}
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            {t.features.subtitle}
          </p>
        </div>
        
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {features.map((feature, index) => (
            <Card key={index} className="bg-card border-border hover:shadow-xl hover:border-primary/20 transition-all duration-300 group">
              <CardContent className="p-6">
                <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mb-4 group-hover:bg-primary/20 transition-colors">
                  <feature.icon className="h-7 w-7 text-primary" />
                </div>
                <h3 className="text-xl font-serif font-semibold text-foreground mb-3">
                  {feature.title}
                </h3>
                <p className="text-muted-foreground leading-relaxed">
                  {feature.description}
                </p>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </section>
  )
}

export function PersonalizationSection() {
  const { t } = useLocale()
  
  return (
    <section className="py-20 bg-background">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="grid lg:grid-cols-2 gap-12 items-center">
          <div>
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-accent/10 border border-accent/20 mb-6">
              <User className="h-4 w-4 text-accent" />
              <span className="text-sm font-medium text-accent">{t.personalization.badge}</span>
            </div>
            <h2 className="text-3xl sm:text-4xl lg:text-5xl font-serif font-bold text-foreground mb-6">
              {t.personalization.title}
              <span className="block text-primary mt-2">{t.personalization.titleHighlight}</span>
            </h2>
            <p className="text-lg text-muted-foreground leading-relaxed mb-6">
              {t.personalization.description}
            </p>
            <ul className="space-y-4 mb-8">
              {t.personalization.steps.map((item, index) => (
                <li key={index} className="flex items-start gap-3">
                  <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-0.5">
                    <div className="w-2 h-2 rounded-full bg-primary" />
                  </div>
                  <span className="text-foreground">{item}</span>
                </li>
              ))}
            </ul>
            <div className="bg-secondary rounded-xl p-5 border border-border">
              <p className="text-sm text-muted-foreground">
                <strong className="text-foreground">{t.personalization.privacyFirst}</strong> {t.personalization.privacyNote} <span className="text-primary font-medium">{t.personalization.privacyHighlight}</span>.
              </p>
            </div>
          </div>
          
          <div className="relative">
            <div className="bg-gradient-to-br from-primary/10 via-secondary to-accent/10 rounded-3xl p-8 border border-border shadow-2xl">
              <div className="space-y-4">
                <div className="flex items-center gap-4 p-4 bg-card rounded-xl border border-border shadow-sm">
                  <div className="w-12 h-12 rounded-xl bg-primary/20 flex items-center justify-center">
                    <BookOpen className="h-6 w-6 text-primary" />
                  </div>
                  <div>
                    <div className="font-semibold text-foreground">{t.personalization.recommendedFor}</div>
                    <div className="text-sm text-muted-foreground">{t.personalization.basedOnInterests}</div>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="p-4 bg-card rounded-xl border border-border shadow-sm">
                    <TrendingUp className="h-5 w-5 text-primary mb-2" />
                    <div className="text-sm text-muted-foreground">{t.personalization.newContent}</div>
                    <div className="text-base font-semibold text-foreground">{t.personalization.addedDaily}</div>
                  </div>
                  <div className="p-4 bg-card rounded-xl border border-border shadow-sm">
                    <Sparkles className="h-5 w-5 text-accent mb-2" />
                    <div className="text-sm text-muted-foreground">{t.personalization.recommendations}</div>
                    <div className="text-base font-semibold text-foreground">{t.personalization.personalizedForYou}</div>
                  </div>
                </div>
                <div className="flex flex-wrap gap-2">
                  {t.personalization.tags.map((tag) => (
                    <span key={tag} className="px-3 py-1.5 bg-secondary rounded-full text-sm text-muted-foreground border border-border">
                      {tag}
                    </span>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}

export function AboutSection() {
  const { t } = useLocale()
  
  return (
    <section id="about" className="py-20 bg-primary text-primary-foreground">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
        <h2 className="text-3xl sm:text-4xl lg:text-5xl font-serif font-bold mb-6">
          {t.about.title}
        </h2>
        <p className="text-xl max-w-3xl mx-auto leading-relaxed mb-8 opacity-90">
          <em className="not-italic font-serif text-2xl">نِبراس</em> {t.about.description} <strong>{'"'}{t.about.lamp}{'"'}</strong> {t.about.or} <strong>{'"'}{t.about.light}{'"'}</strong>{t.about.descriptionContinue}
        </p>
        <div className="grid md:grid-cols-3 gap-8 max-w-4xl mx-auto">
          {t.about.pillars.map((item, index) => (
            <div key={index} className="text-center p-6 rounded-2xl bg-primary-foreground/5">
              <h3 className="text-2xl font-serif font-semibold mb-3">{item.title}</h3>
              <p className="opacity-80 leading-relaxed">{item.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}

export function GrowthSection() {
  const { t } = useLocale()
  
  const icons = [TrendingUp, Sparkles, Star]
  const cards = t.growth.cards.map((card, index) => ({
    icon: icons[index],
    ...card
  }))

  return (
    <section className="py-20 bg-secondary">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-12">
          <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-accent/10 border border-accent/20 mb-6">
            <Rocket className="h-4 w-4 text-accent" />
            <span className="text-sm font-medium text-accent">{t.growth.badge}</span>
          </div>
          <h2 className="text-3xl sm:text-4xl lg:text-5xl font-serif font-bold text-foreground mb-4">
            {t.growth.title}
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            {t.growth.subtitle}
          </p>
        </div>
        
        <div className="grid md:grid-cols-3 gap-6">
          {cards.map((card, index) => (
            <Card key={index} className="bg-card border-border text-center p-6">
              <CardContent className="p-0">
                <div className="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center mx-auto mb-4">
                  <card.icon className="h-8 w-8 text-primary" />
                </div>
                <h3 className="text-xl font-serif font-semibold text-foreground mb-2">{card.title}</h3>
                <p className="text-muted-foreground">{card.description}</p>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    </section>
  )
}

export function CTASection() {
  const { t } = useLocale()
  
  return (
    <section className="py-20 bg-background">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
        <div className="bg-gradient-to-br from-primary/5 via-secondary to-accent/5 rounded-3xl p-10 border border-border">
          <h2 className="text-3xl sm:text-4xl lg:text-5xl font-serif font-bold text-foreground mb-6">
            {t.cta.title}
          </h2>
          <p className="text-lg text-muted-foreground mb-8 max-w-2xl mx-auto">
            {t.cta.description}
          </p>
          <Button size="lg" className="px-10 py-6 text-lg" asChild>
            <a href="https://play.google.com/store" target="_blank" rel="noopener noreferrer">
              {t.cta.downloadBtn}
            </a>
          </Button>
        </div>
      </div>
    </section>
  )
}
