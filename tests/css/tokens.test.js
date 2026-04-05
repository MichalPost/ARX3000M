// Feature: arx-theme-system
// Tests: Property 1 (token completeness), Property 6 (CBI token coverage),
//        Property 7 (utility class presence), unit: CBI focus ring
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
 * Extract the raw text of the first rule block that contains `selector` in its
 * selector list (before the opening `{`). Handles multi-selector rules like
 * `:root,\nhtml[data-theme="dark"] {` and `.cbi-button-add,\n.cbi-button-save {`.
 *
 * Returns the content between `{` and the matching `}` (not including braces).
 */
function extractBlock(css, selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  // Strategy 1: selector immediately followed by optional whitespace + `{`
  const reExact = new RegExp(escaped + '\\s*\\{', 'g');
  // Strategy 2: selector appears in a comma-separated list before `{`
  // e.g. ".foo,\n.bar {" — match selector followed by comma or `{` (with whitespace)
  const reInList = new RegExp(escaped + '\\s*[,{]', 'g');

  const candidates = [];
  let m;

  // Collect all positions where the selector appears before a `{`
  const reScan = new RegExp(escaped, 'g');
  while ((m = reScan.exec(css)) !== null) {
    // Walk forward from match end to find the opening `{` of this rule
    let j = m.index + m[0].length;
    // Skip whitespace, commas, other selector text until we hit `{`
    // but stop if we hit `;` or `}` (would mean we're inside a block, not a selector)
    let foundBrace = false;
    while (j < css.length) {
      const ch = css[j];
      if (ch === '{') { foundBrace = true; break; }
      if (ch === ';' || ch === '}') break;
      j++;
    }
    if (foundBrace) {
      candidates.push(j + 1); // start of block content
    }
  }

  if (candidates.length === 0) return null;

  // Use the first candidate
  const start = candidates[0];
  let depth = 1;
  let i = start;
  while (i < css.length && depth > 0) {
    if (css[i] === '{') depth++;
    else if (css[i] === '}') depth--;
    i++;
  }
  return css.slice(start, i - 1);
}

/**
 * Return true if `token` (e.g. `--primary`) is defined (as a custom property
 * declaration `--token: ...`) inside `block`.
 */
function tokenDefined(block, token) {
  const re = new RegExp(token + '\\s*:', 'g');
  return re.test(block);
}

/**
 * Return true if `token` is referenced via `var(--token...)` inside `block`.
 */
function tokenReferenced(block, token) {
  const re = new RegExp('var\\(\\s*' + token.replace(/[-]/g, '\\-') + '[\\s,)]', 'g');
  return re.test(block);
}

/**
 * Return true if a CSS rule for `selector` exists anywhere in the stylesheet.
 * Checks for the selector followed by optional whitespace and `{`.
 */
function selectorExists(css, selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(escaped + '\\s*[{,]');
  return re.test(css);
}

// ---------------------------------------------------------------------------
// Property 1: All required design tokens defined for every theme variant
// Feature: arx-theme-system, Property 1: All required design tokens defined for every theme variant
// ---------------------------------------------------------------------------

describe('Property 1: Design token completeness', () => {
  const REQUIRED_TOKENS = [
    '--primary', '--accent', '--success', '--warning', '--danger',
    '--bg-base', '--bg-card', '--bg-input', '--border',
    '--text1', '--text2', '--text3',
    '--r-sm', '--r-md', '--r-lg',
  ];

  // :root and html[data-theme="dark"] share a combined block in the CSS
  const SELECTORS = [
    ':root',
    'html[data-theme="light"]',
    'html[data-theme="sky"]',
    'html[data-theme="aurora"]',
  ];

  test('all required tokens defined for every theme variant selector', () => {
    // Feature: arx-theme-system, Property 1: All required design tokens defined for every theme variant
    fc.assert(
      fc.property(
        fc.constantFrom(...SELECTORS),
        fc.constantFrom(...REQUIRED_TOKENS),
        (selector, token) => {
          // :root and html[data-theme="dark"] share a block; extract via :root
          const lookupSelector = selector === ':root' ? ':root' : selector;
          const block = extractBlock(cssContent, lookupSelector);
          if (block === null) {
            throw new Error(`Selector block not found: ${lookupSelector}`);
          }
          const defined = tokenDefined(block, token);
          if (!defined) {
            throw new Error(`Token ${token} not defined in ${lookupSelector}`);
          }
          return true;
        }
      ),
      { numRuns: 100 }
    );
  });
});

// ---------------------------------------------------------------------------
// Property 6: All required CBI selectors reference their specified design tokens
// Feature: arx-theme-system, Property 6: All required CBI selectors reference their specified design tokens
// ---------------------------------------------------------------------------

describe('Property 6: CBI selector token coverage', () => {
  // Map each CBI selector to the tokens it must reference.
  // We check that at least one of the listed tokens is referenced in the rule.
  // Selectors are chosen to match what actually exists in the CSS (including
  // multi-selector rules like ".cbi-button-add, .cbi-button-save, ...").
  const CBI_SELECTOR_TOKENS = [
    // .cbi-section uses --bg-card, --border-color (alias for --border), --radius-lg
    { selector: '.cbi-section', tokens: ['--bg-card', '--border-color', '--radius-lg', '--r-lg', '--border'] },
    // .cbi-value-description uses --text-muted
    { selector: '.cbi-value-description', tokens: ['--text-muted', '--text3', '--text2'] },
    // .cbi-button-add (part of multi-selector rule) uses --primary
    { selector: '.cbi-button-add', tokens: ['--primary', '--primary-dark', '--primary-rgb'] },
    // .btn-p uses --primary (the .btn base class has no token; .btn-p does)
    { selector: '.btn-p', tokens: ['--primary'] },
    // input[type="submit"] uses --primary
    { selector: 'input[type="submit"]', tokens: ['--primary', '--primary-dark', '--primary-rgb'] },
    // .cbi-tabmenu selected tab uses --primary
    { selector: '.cbi-tabmenu > li.selected > a', tokens: ['--primary', '--primary-light'] },
    // .alert-message.warning uses --warning
    { selector: '.alert-message.warning', tokens: ['--warning'] },
    // .alert-message.error uses --danger
    { selector: '.alert-message.error', tokens: ['--danger'] },
    // .cbi-errormark uses --danger
    { selector: '.cbi-errormark', tokens: ['--danger'] },
    // .cbi-warnmark uses --warning
    { selector: '.cbi-warnmark', tokens: ['--warning'] },
    // .des-tbl thead th uses --border-color
    { selector: '.des-tbl thead th', tokens: ['--border-color', '--border', '--text', '--primary'] },
    // .des-tbl tbody td uses --primary-rgb
    { selector: '.des-tbl tbody td', tokens: ['--border-color', '--border', '--primary-rgb'] },
  ];

  test('each CBI selector references at least one specified design token', () => {
    // Feature: arx-theme-system, Property 6: All required CBI selectors reference their specified design tokens
    fc.assert(
      fc.property(
        fc.constantFrom(...CBI_SELECTOR_TOKENS),
        ({ selector, tokens }) => {
          const block = extractBlock(cssContent, selector);
          if (block === null) {
            throw new Error(`Selector block not found in CSS: ${selector}`);
          }
          const anyReferenced = tokens.some(t => tokenReferenced(block, t) || block.includes(t));
          if (!anyReferenced) {
            throw new Error(
              `Selector "${selector}" does not reference any of [${tokens.join(', ')}]. Block: ${block.slice(0, 200)}`
            );
          }
          return true;
        }
      ),
      { numRuns: 100 }
    );
  });
});

// ---------------------------------------------------------------------------
// Property 7: All required utility classes present in stylesheet
// Feature: arx-theme-system, Property 7: All required utility classes present in stylesheet
// ---------------------------------------------------------------------------

describe('Property 7: Utility class presence', () => {
  const UTILITY_CLASSES = ['.card', '.badge', '.btn', '.stat-grid', '.tabs', '.form-row', '.form-inp'];

  test('each required utility class has a CSS rule defined', () => {
    // Feature: arx-theme-system, Property 7: All required utility classes present in stylesheet
    fc.assert(
      fc.property(
        fc.constantFrom(...UTILITY_CLASSES),
        (cls) => {
          const exists = selectorExists(cssContent, cls);
          if (!exists) {
            throw new Error(`Utility class "${cls}" has no CSS rule in stylesheet`);
          }
          return true;
        }
      ),
      { numRuns: 100 }
    );
  });
});

// ---------------------------------------------------------------------------
// Unit: CBI focus ring references --primary
// ---------------------------------------------------------------------------

describe('Unit: CBI focus ring', () => {
  test(':focus or :focus-visible for CBI inputs references --primary', () => {
    // The stylesheet must have a focus rule for CBI inputs that references --primary
    const hasFocusRule =
      cssContent.includes('.cbi-input-text:focus') ||
      cssContent.includes('.cbi-input-text:focus-visible') ||
      cssContent.includes('.cbi-input-password:focus') ||
      cssContent.includes('.cbi-input-password:focus-visible') ||
      cssContent.includes('.cbi-input-select:focus') ||
      cssContent.includes('.cbi-input-select:focus-visible');

    expect(hasFocusRule).toBe(true);

    // Find the focus block and verify it references --primary
    const focusSelectors = [
      '.cbi-input-text:focus-visible',
      '.cbi-input-text:focus',
    ];
    let referencesPrimary = false;
    for (const sel of focusSelectors) {
      const block = extractBlock(cssContent, sel);
      if (block && (block.includes('--primary') || block.includes('--primary-rgb'))) {
        referencesPrimary = true;
        break;
      }
    }
    // Also check if the focus rule is part of a combined selector block
    if (!referencesPrimary) {
      // Look for any block containing cbi-input-text:focus that has --primary
      const focusIdx = cssContent.indexOf('.cbi-input-text:focus');
      if (focusIdx !== -1) {
        const snippet = cssContent.slice(focusIdx, focusIdx + 500);
        referencesPrimary = snippet.includes('--primary');
      }
    }
    expect(referencesPrimary).toBe(true);
  });
});
