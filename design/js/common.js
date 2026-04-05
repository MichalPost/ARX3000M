// ARX3000M Demo — Common
(function () {
  // ── Theme ──
  var THEME_LABELS = { dark:'🌙 深色', light:'☀️ 浅色', sky:'🌊 天蓝', aurora:'✨ 极光' };

  function getTheme() { try { return localStorage.getItem('arx-theme') || 'dark'; } catch(e) { return 'dark'; } }
  function setTheme(t) {
    document.documentElement.setAttribute('data-theme', t);
    try { localStorage.setItem('arx-theme', t); } catch(e) {}
    document.querySelectorAll('.theme-opt').forEach(function(el) {
      el.classList.toggle('active', el.dataset.theme === t);
    });
    var lbl = document.getElementById('theme-btn-label');
    if (lbl) lbl.textContent = THEME_LABELS[t] || t;
  }

  // ── Theme picker ──
  function initThemePicker() {
    var btn  = document.getElementById('theme-picker-btn');
    var menu = document.getElementById('theme-menu');
    if (!btn || !menu) return;
    btn.addEventListener('click', function(e) { e.stopPropagation(); menu.classList.toggle('open'); });
    document.addEventListener('click', function() { menu.classList.remove('open'); });
    menu.querySelectorAll('.theme-opt').forEach(function(el) {
      el.addEventListener('click', function() { setTheme(el.dataset.theme); menu.classList.remove('open'); });
    });
  }

  // ── Sidebar layout ──
  var LAYOUTS = ['expanded','narrow','hidden'];
  var LAYOUT_LABELS = { expanded:'展开', narrow:'窄栏', hidden:'隐藏' };

  function getLayout() { try { return localStorage.getItem('arx-sidebar-mode') || 'expanded'; } catch(e) { return 'expanded'; } }
  function setLayout(m) {
    document.documentElement.setAttribute('data-arx-sidebar', m);
    try { localStorage.setItem('arx-sidebar-mode', m); } catch(e) {}
    document.querySelectorAll('.layout-opt').forEach(function(el) {
      el.classList.toggle('active', el.dataset.layout === m);
    });
    var lbl = document.getElementById('layout-btn-label');
    if (lbl) lbl.textContent = LAYOUT_LABELS[m] || m;
  }
  window.setLayout = setLayout;

  function initLayoutPicker() {
    // Use event delegation — logo icon id is set after sidebar.js render()
    document.addEventListener('click', function(e) {
      // logo icon → cycle layout
      if (e.target.closest('#sb-logo-icon')) {
        var cur = getLayout();
        var idx = LAYOUTS.indexOf(cur);
        setLayout(LAYOUTS[(idx + 1) % LAYOUTS.length]);
        return;
      }
      // hamburger button → restore to expanded
      if (e.target.closest('#topbar-menu-btn')) {
        setLayout('expanded');
      }
    });
    // Ctrl+Shift+B cycle
    document.addEventListener('keydown', function(e) {
      if (e.ctrlKey && e.shiftKey && e.key === 'B') {
        var cur = getLayout();
        var idx = LAYOUTS.indexOf(cur);
        setLayout(LAYOUTS[(idx + 1) % LAYOUTS.length]);
      }
    });
  }

  // ── Toast ──
  window.ARX = {
    toast: function(msg, type) {
      var t = document.createElement('div');
      t.textContent = msg;
      var bg = { success:'#22c55e', danger:'#ef4444', warning:'#f59e0b' }[type] || '#6366f1';
      t.style.cssText = 'position:fixed;bottom:22px;right:22px;z-index:9999;padding:9px 16px;'
        + 'border-radius:8px;font-size:13px;font-weight:500;color:#fff;'
        + 'box-shadow:0 4px 16px rgba(0,0,0,.4);animation:fadeUp .3s ease;background:' + bg;
      document.body.appendChild(t);
      setTimeout(function() { t.remove(); }, 2800);
    }
  };

  // ── Init ──
  document.addEventListener('DOMContentLoaded', function() {
    // apply saved theme immediately
    setTheme(getTheme());
    setLayout(getLayout());
    initThemePicker();
    initLayoutPicker();

    // render sidebar if container exists
    var nav = document.getElementById('sb-nav');
    if (nav && window.ARX_SIDEBAR) {
      ARX_SIDEBAR.render('sb-nav');
    }

    // clock
    var clk = document.getElementById('topbar-clock');
    if (clk) {
      function tick() { clk.textContent = '🕐 ' + new Date().toLocaleTimeString('zh-CN'); }
      tick(); setInterval(tick, 1000);
    }
  });
})();
