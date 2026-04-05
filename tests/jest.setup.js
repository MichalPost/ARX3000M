// Global jsdom polyfills required by arx.js
// IntersectionObserver is used by initAnimations() — not available in jsdom
global.IntersectionObserver = class IntersectionObserver {
  constructor() {}
  observe() {}
  unobserve() {}
  disconnect() {}
};

// matchMedia default stub (tests override per-case as needed)
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: jest.fn().mockImplementation(query => ({
    matches: false,
    media: query,
    addEventListener: jest.fn(),
    addListener: jest.fn(),
    removeEventListener: jest.fn(),
    removeListener: jest.fn(),
  })),
});
