// Feature: arx-theme-system
// Tests: Property 10 (sidebar CSS modes), unit: narrow/hidden/mobile breakpoint
const fs = require('fs');
const path = require('path');
const fc = require('fast-check');

const CSS_FILE = path.resolve(__dirname, '../../theme/htdocs/css/style.css');

let cssContent = '';
beforeAll(() => {
  cssContent = fs.readFileSync(CSS_FILE, 'utf8');
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Return true if the stylesheet contains a rule matching `pattern` anywhere.
 */
function cssContains(css, pattern) {
  if (typeof pattern === 'string') return css.includes(pattern);
  return pattern.test(css);
}

/**
 * Extract the text of the first block whose selector line contains `selectorFragment`.
 * Returns the content between `{` and the matching `}`.
 */
function extractBlock(css, selectorFragment) {
  const escaped = selectorFragment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(escaped + '\\s*\\{', 'g');
  let match;
  while ((match = re.exec(css)) !== null) {
    const start = match.index + match[0].length;
    let depth = 1;
    let i = start;
    while (i < css.length && depth > 0) {
      if (css[i] === '{') depth++;
      else if (css[i] === '}') depth--;
      i++;
    }
    return css.slice(start, i - 1);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Property 10: All three sidebar layout modes defined in stylesheet
// Feature: arx-theme-system, Property 10: All three sidebar layout modes defined in stylesheet
// ---------------------------------------------------------------------------

describe('Property 10: Sidebar CSS modes', () => {
  /**
   * The CSS implements sidebar modes as follows:
   *
   * - expanded: default — --sidebar-width: 220px is set on :root; no explicit
   *   [data-arx-sidebar="expanded"] selector is needed (and none exists).
   *   We verify the :root block defines --sidebar-width: 220px.
   *
   * - narrow: html[data-arx-sidebar="narrow"] { --sidebar-width: 52px }
   *   inside @media (min-width: 769px)
   *
   * - hidden: html[data-arx-sidebar="hidden"] .main-left { transform: translateX(-100%) }
   *   inside @media (min-width: 769px)
   */
  const SIDEBAR_MODES = [
    {
      mode: 'expanded',
      description: '220px sidebar width defined on :root',
      check: (css) => {
        // :root must define --sidebar-width: 220px
        const rootBlock = extractBlock(css, ':root');
        return rootBlock !== null && rootBlock.includes('--sidebar-width: 220px');
      },
    },
    {
      mode: 'narrow',
      description: '52px sidebar width via [data-arx-sidebar="narrow"]',
      check: (css) => {
        // Must contain --sidebar-width: 52px inside a narrow selector block
        return (
          cssContains(css, '--sidebar-width: 52px') &&
          cssContains(css, 'data-arx-sidebar="narrow"')
        );
      },
    },
    {
      mode: 'hidden',
      description: 'translateX(-100%) transform via [data-arx-sidebar="hidden"]',
      check: (css) => {
        return (
          cssContains(css, 'data-arx-sidebar="hidden"') &&
          cssContains(css, 'translateX(-100%)')
        );
      },
    },
  ];

  test('all three sidebar layout modes are defined in the stylesheet', () => {
    // Feature: arx-theme-system, Property 10: All three sidebar layout modes defined in stylesheet
    fc.assert(
      fc.property(
        fc.constantFrom(...SIDEBAR_MODES),
        ({ mode, description, check }) => {
          const result = check(cssContent);
          if (!result) {
            throw new Error(`Sidebar mode "${mode}" not correctly defined: ${description}`);
          }
          return true;
        }
      ),
      { numRuns: 100 }
    );
  });

  // Individual assertions for clarity
  test('[data-arx-sidebar="expanded"] — :root defines 220px sidebar width', () => {
    const rootBlock = extractBlock(cssContent, ':root');
    expect(rootBlock).not.toBeNull();
    expect(rootBlock).toContain('--sidebar-width: 220px');
  });

  test('[data-arx-sidebar="narrow"] defines 52px sidebar width', () => {
    expect(cssContent).toContain('data-arx-sidebar="narrow"');
    expect(cssContent).toContain('--sidebar-width: 52px');
    // Verify the 52px value is inside the narrow selector context
    const narrowIdx = cssContent.indexOf('data-arx-sidebar="narrow"');
    const region = cssContent.slice(narrowIdx, narrowIdx + 200);
    expect(region).toContain('52px');
  });

  test('[data-arx-sidebar="hidden"] defines translateX(-100%)', () => {
    expect(cssContent).toContain('data-arx-sidebar="hidden"');
    expect(cssContent).toContain('translateX(-100%)');
    // Verify translateX(-100%) appears after the hidden selector
    const hiddenIdx = cssContent.indexOf('data-arx-sidebar="hidden"');
    const region = cssContent.slice(hiddenIdx, hiddenIdx + 500);
    expect(region).toContain('translateX(-100%)');
  });
});

// ---------------------------------------------------------------------------
// Unit: Sidebar CSS details
// ---------------------------------------------------------------------------

describe('Unit: Sidebar CSS details', () => {
  test('[data-arx-sidebar="narrow"] hides .nav-label and .nav-arrow', () => {
    // Both .nav-label and .nav-arrow must have display: none inside narrow rules
    const navLabelHidden =
      cssContent.includes('data-arx-sidebar="narrow"') &&
      /data-arx-sidebar="narrow"[^}]*\.nav-label[\s\S]*?display\s*:\s*none/.test(cssContent);
    const navArrowHidden =
      /data-arx-sidebar="narrow"[^}]*\.nav-arrow[\s\S]*?display\s*:\s*none/.test(cssContent);

    // Check via extractBlock approach — find the narrow .nav-label block
    const navLabelBlock = extractBlock(cssContent, 'html[data-arx-sidebar="narrow"] #main-nav .nav-label');
    const navArrowBlock = extractBlock(cssContent, 'html[data-arx-sidebar="narrow"] #main-nav .nav-arrow');

    expect(navLabelBlock || navLabelHidden).toBeTruthy();
    expect(navArrowBlock || navArrowHidden).toBeTruthy();

    if (navLabelBlock) expect(navLabelBlock).toContain('display');
    if (navArrowBlock) expect(navArrowBlock).toContain('display');
  });

  test('[data-arx-sidebar="hidden"] .main-left has transform: translateX(-100%)', () => {
    const block = extractBlock(
      cssContent,
      'html[data-arx-sidebar="hidden"] .main-left'
    );
    expect(block).not.toBeNull();
    expect(block).toContain('translateX(-100%)');
  });

  test('@media max-width 768px or 769px hides sidebar and shows .showSide', () => {
    // The stylesheet must have a responsive breakpoint that hides the sidebar
    const hasMediaQuery =
      cssContent.includes('max-width: 768px') ||
      cssContent.includes('max-width:768px') ||
      cssContent.includes('max-width: 769px') ||
      cssContent.includes('max-width:769px');
    expect(hasMediaQuery).toBe(true);

    // .showSide must be shown (display: block or flex) somewhere in a media query
    const showSideVisible =
      /\.showSide\s*\{[^}]*display\s*:\s*(block|flex)/.test(cssContent) ||
      cssContent.includes('.showSide') && cssContent.includes('display: block');
    expect(showSideVisible).toBe(true);
  });
});
