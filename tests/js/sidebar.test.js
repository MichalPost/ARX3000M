// Feature: arx-theme-system
// Tests: Property 9 (sidebar localStorage round-trip)
// Tag format: Feature: arx-theme-system, Property 9: <property_text>

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
  document.documentElement.removeAttribute('data-arx-sidebar');
});

// Feature: arx-theme-system, Property 9: Sidebar mode round-trip through localStorage
describe('Property 9: Sidebar mode localStorage round-trip', () => {
  const SIDEBAR_MODES = ['expanded', 'narrow', 'hidden'];

  test('setSidebarMode writes arx-sidebar-mode to localStorage', () => {
    // Property: for any valid sidebar mode, setSidebarMode must persist it to localStorage
    fc.assert(
      fc.property(fc.constantFrom(...SIDEBAR_MODES), (mode) => {
        ARXTheme.setSidebarMode(mode);
        expect(localStorage.getItem('arx-sidebar-mode')).toBe(mode);
      }),
      { numRuns: SIDEBAR_MODES.length }
    );
  });

  test('setSidebarMode sets data-arx-sidebar on <html>', () => {
    // Property: for any valid sidebar mode, setSidebarMode must set the attribute
    fc.assert(
      fc.property(fc.constantFrom(...SIDEBAR_MODES), (mode) => {
        ARXTheme.setSidebarMode(mode);
        expect(document.documentElement.getAttribute('data-arx-sidebar')).toBe(mode);
      }),
      { numRuns: SIDEBAR_MODES.length }
    );
  });

  test('setSidebarMode then initSidebarMode restores the same mode', () => {
    // Property: for any valid mode, after setSidebarMode → clear attribute → initSidebarMode,
    // data-arx-sidebar must be restored to the same mode
    fc.assert(
      fc.property(fc.constantFrom(...SIDEBAR_MODES), (mode) => {
        ARXTheme.setSidebarMode(mode);
        // Simulate page reload: clear the attribute but keep localStorage
        document.documentElement.removeAttribute('data-arx-sidebar');
        ARXTheme.initSidebarMode();
        expect(document.documentElement.getAttribute('data-arx-sidebar')).toBe(mode);
      }),
      { numRuns: SIDEBAR_MODES.length }
    );
  });

  test('initSidebarMode defaults to expanded when localStorage is empty', () => {
    localStorage.clear();
    document.documentElement.removeAttribute('data-arx-sidebar');
    ARXTheme.initSidebarMode();
    expect(document.documentElement.getAttribute('data-arx-sidebar')).toBe('expanded');
  });

  test('setSidebarMode with invalid mode falls back to expanded', () => {
    ARXTheme.setSidebarMode('invalid-mode');
    expect(document.documentElement.getAttribute('data-arx-sidebar')).toBe('expanded');
  });

  test('cycleSidebarMode advances through expanded → narrow → hidden → expanded', () => {
    // Start from expanded
    ARXTheme.setSidebarMode('expanded');
    ARXTheme.cycleSidebarMode();
    expect(document.documentElement.getAttribute('data-arx-sidebar')).toBe('narrow');

    ARXTheme.cycleSidebarMode();
    expect(document.documentElement.getAttribute('data-arx-sidebar')).toBe('hidden');

    ARXTheme.cycleSidebarMode();
    expect(document.documentElement.getAttribute('data-arx-sidebar')).toBe('expanded');
  });
});
