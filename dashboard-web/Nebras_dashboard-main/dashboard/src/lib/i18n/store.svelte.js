import { translations } from './translations.js';

// Get default from localStorage if available, otherwise 'ar'
function getStoredLanguage() {
    if (typeof window === 'undefined') return 'ar';
    return localStorage.getItem('nebras_lang') || 'ar';
}

function getStoredDir(lang) {
    if (lang === 'ar') return 'rtl';
    return 'ltr';
}

// Reactive state
let state = $state({
    locale: getStoredLanguage(),
    dir: getStoredDir(getStoredLanguage())
});

export function setLanguage(lang) {
    state.locale = lang;
    state.dir = lang === 'ar' ? 'rtl' : 'ltr';
    if (typeof window !== 'undefined') {
        localStorage.setItem('nebras_lang', lang);
        document.documentElement.lang = lang;
        document.documentElement.dir = state.dir;
    }
}

export function toggleLanguage() {
    const newLang = state.locale === 'ar' ? 'en' : 'ar';
    setLanguage(newLang);
}

export function getLanguage() {
    return state.locale;
}

export function getDir() {
    return state.dir;
}

/**
 * Super simple translation function.
 * Allows nested keys like "sidebar.dashboard"
 * Does not support interpolation yet, but we can add it if needed.
 */
export function t(key) {
    const keys = key.split('.');
    let value = translations[state.locale];

    for (const k of keys) {
        if (value && typeof value === 'object' && k in value) {
            value = value[k];
        } else {
            return key; // return key itself if missing
        }
    }

    return value || key;
}
