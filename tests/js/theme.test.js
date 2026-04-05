// Feature: arx-theme-system
// Tests: Property 2 (theme switching), Property 3 (localStorage round-trip),
//        Property 4 (system preference fallback)
// Tag format: Feature: arx-theme-system, Property N: <property_text>

const fc = require('fast-check');

let ARXTheme;

beforeAll(() => {
  const fs = require('fs');
  const path = require('path');
  const src = fs.readFileSync(
    path.resolve(__dirname, '../../theme/htdocs/js/arx.js'),
    'utf8'
  );
  // arx.js is an IIFE that attaches ARXTheme to window — load it in jsdom context
  // eslint-disable-next-line no-new-func
  new Function('window', 'document', 'localStorage', src)(window, document, localStorage);
  ARXTheme = window.ARXTheme;
});

beforeEach(() => {
  localStorage.clear();
  document.documentElement.removeAttribute('data-theme');
  document.documentElement.removeAttribute('data-arx-sidebar');
  // Reset matchMedia to default stub (light system preference — matches: false for dark)
  window.matchMedia = jest.fn().mockImplementation(query => ({
    matches: false,
    media: query,
    addEventListener: jest.fn(),
    addListener: jest.fn(),
    removeEventListener: jest.fn(),
    removeListener: jest.fn(),
  }));
});

// Feature: arx-theme-system, Property 2: Theme switching applies correct tokens without page reload
describe('Property 2: Theme switching', () => {
  const THEME_IDS = ['dark', 'light', 'sky', 'aurora'];

  test('setTheme sets data-theme on <html> for each valid theme ID', () => {
    // Property: for any valid theme ID, setTheme must set data-theme to that ID
    fc.assert(
      fc.property(fc.constantFrom(...THEME_IDS), (themeId) => {
        ARXTheme.setTheme(themeId);
        expect(document.documentElement.getAttribute('data-theme')).toBe(themeId);
      }),
      { numRuns: THEME_IDS.length }
    );
  });

  test('setTheme writes arx-theme to localStorage', () => {
    // Property: for any valid theme ID, setTheme must persist it to localStorage
    fc.assert(
      fc.property(fc.constantFrom(...THEME_IDS), (themeId) => {
        ARXTheme.setTheme(themeId);
        expect(localStorage.getItem('arx-theme')).toBe(themeId);
      }),
      { numRuns: THEME_IDS.length }
    );
  });

  test('setTheme sets arx-theme-user-set to "1"', () => {
    fc.assert(
      fc.property(fc.constantFrom(...THEME_IDS), (themeId) => {
        ARXTheme.setTheme(themeId);
        expect(localStorage.getItem('arx-theme-user-set')).toBe('1');
      }),
      { numRuns: THEME_IDS.length }
    );
  });

  test('setTheme with invalid ID falls back to light', () => {
    ARXTheme.setTheme('invalid-theme');
    expect(document.documentElement.getAttribute('data-theme')).toBe('light');
  });
});

// Feature: arx-theme-system, Property 3: Theme preference round-trip through localStorage
describe('Property 3: Theme localStorage round-trip', () => {
  const THEME_IDS = ['dark', 'light', 'sky', 'aurora'];

  test('setTheme then applyThemeFromPrefs restores the same theme', () => {
    // Property: for any valid theme ID, after setTheme → clear attribute → applyThemeFromPrefs,
    // data-theme must be restored to the same ID
    fc.assert(
      fc.property(fc.constantFrom(...THEME_IDS), (themeId) => {
        ARXTheme.setTheme(themeId);
        // Simulate page reload: clear the attribute but keep localStorage
        document.documentElement.removeAttribute('data-theme');
        ARXTheme.applyThemeFromPrefs();
        expect(document.documentElement.getAttribute('data-theme')).toBe(themeId);
      }),
      { numRuns: THEME_IDS.length }
    );
  });

  test('round-trip preserves sky and aurora without user lock', () => {
    // sky and aurora are sticky non-system themes — they survive even without user lock
    ['sky', 'aurora'].forEach((themeId) => {
      localStorage.clear();
      localStorage.setItem('arx-theme', themeId);
      // No arx-theme-user-set key set
      document.documentElement.removeAttribute('data-theme');
      ARXTheme.applyThemeFromPrefs();
      expect(document.documentElement.getAttribute('data-theme')).toBe(themeId);
    });
  });
});

// Feature: arx-theme-system, Property 4: System preference followed when no user lock is set
describe('Property 4: System preference fallback', () => {
  test('applyThemeFromPrefs sets dark when prefers-color-scheme is dark and no user lock', () => {
    // Mock matchMedia to report dark preference
    window.matchMedia = jest.fn().mockImplementation(query => ({
      matches: query === '(prefers-color-scheme: dark)',
      media: query,
      addEventListener: jest.fn(),
      addListener: jest.fn(),
      removeEventListener: jest.fn(),
      removeListener: jest.fn(),
    }));

    localStorage.clear(); // No user lock, no saved theme
    document.documentElement.removeAttribute('data-theme');
    ARXTheme.applyThemeFromPrefs();
    expect(document.documentElement.getAttribute('data-theme')).toBe('dark');
  });

  test('applyThemeFromPrefs sets light when prefers-color-scheme is light and no user lock', () => {
    // matchMedia returns false for dark (already set in beforeEach)
    localStorage.clear();
    document.documentElement.removeAttribute('data-theme');
    ARXTheme.applyThemeFromPrefs();
    expect(document.documentElement.getAttribute('data-theme')).toBe('light');
  });

  test('user lock overrides system preference', () => {
    // When arx-theme-user-set is set, system preference must be ignored
    window.matchMedia = jest.fn().mockImplementation(query => ({
      matches: query === '(prefers-color-scheme: dark)',
      media: query,
      addEventListener: jest.fn(),
      addListener: jest.fn(),
      removeEventListener: jest.fn(),
      removeListener: jest.fn(),
    }));

    localStorage.setItem('arx-theme', 'sky');
    localStorage.setItem('arx-theme-user-set', '1');
    document.documentElement.removeAttribute('data-theme');
    ARXTheme.applyThemeFromPrefs();
    // Should use user-locked 'sky', not system 'dark'
    expect(document.documentElement.getAttribute('data-theme')).toBe('sky');
  });

  test('property: for each system preference value, applyThemeFromPrefs follows it when no lock', () => {
    // Property: for any prefers-color-scheme value (dark/light), applyThemeFromPrefs must match
    fc.assert(
      fc.property(fc.constantFrom('dark', 'light'), (sysPref) => {
        window.matchMedia = jest.fn().mockImplementation(query => ({
          matches: query === '(prefers-color-scheme: dark)' && sysPref === 'dark',
          media: query,
          addEventListener: jest.fn(),
          addListener: jest.fn(),
          removeEventListener: jest.fn(),
          removeListener: jest.fn(),
        }));

        localStorage.clear();
        document.documentElement.removeAttribute('data-theme');
        ARXTheme.applyThemeFromPrefs();
        expect(document.documentElement.getAttribute('data-theme')).toBe(sysPref);
      }),
      { numRuns: 2 }
    );
  });
});
