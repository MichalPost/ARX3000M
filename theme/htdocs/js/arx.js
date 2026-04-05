(function() {
    'use strict';

    var THEME_IDS = ['dark', 'light', 'sky', 'aurora'];
    var LS_THEME = 'arx-theme';
    var LS_THEME_LOCK = 'arx-theme-user-set';
    var LS_DEVICES = 'arx-known-devices';
    var SS_REMEMBER = 'arx-remember-device';
    var SS_PENDING_USER = 'arx-pending-username';
    var SS_NAV_SKEL = 'arx-nav-skeleton';
    var LS_SIDEBAR = 'arx-sidebar-mode';
    var SIDEBAR_MODES = ['expanded', 'narrow', 'hidden'];

    var ARXTheme = {
        version: '2.9.0',
        THEMES: [
            { id: 'dark', label: '深色' },
            { id: 'light', label: '浅色' },
            { id: 'sky', label: '天蓝' },
            { id: 'aurora', label: '极光渐变' }
        ],

        init: function() {
            this.initSidebarMode();
            this.initTheme();
            this.initThemePicker();
            this.initSidebarLayoutMenu();
            this.initSidebar();
            this.initStatusCards();
            this.initAnimations();
            this.initStatusBar();
            this.initCopyButtons();
            this.initKeyboardShortcuts();
            this.initTooltips();
            this.initTrustedDevices();
            this.initPageSkeleton();
            this.initNavSkeletonCapture();
            this.initPrefersColorScheme();
            this.initModalA11y();
        },

        applyThemeFromPrefs: function() {
            var userLocked = false;
            var saved = null;
            try {
                userLocked = localStorage.getItem(LS_THEME_LOCK) === '1';
                saved = localStorage.getItem(LS_THEME);
            } catch (e) {}
            if (userLocked) {
                var t = (saved && THEME_IDS.indexOf(saved) >= 0) ? saved : 'light';
                document.documentElement.setAttribute('data-theme', t);
                this.syncThemeUI(t);
                return;
            }
            if (saved === 'sky' || saved === 'aurora') {
                if (THEME_IDS.indexOf(saved) < 0) saved = 'light';
                document.documentElement.setAttribute('data-theme', saved);
                this.syncThemeUI(saved);
                return;
            }
            var sys = 'light';
            try {
                if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) sys = 'dark';
            } catch (e2) {}
            document.documentElement.setAttribute('data-theme', sys);
            this.syncThemeUI(sys);
        },

        initTheme: function() {
            this.applyThemeFromPrefs();
        },

        initPrefersColorScheme: function() {
            var self = this;
            try {
                var mq = window.matchMedia('(prefers-color-scheme: dark)');
                function onChange() {
                    try {
                        if (localStorage.getItem(LS_THEME_LOCK) === '1') return;
                        var s = localStorage.getItem(LS_THEME);
                        if (s === 'sky' || s === 'aurora') return;
                        self.applyThemeFromPrefs();
                    } catch (e) {}
                }
                if (mq.addEventListener) mq.addEventListener('change', onChange);
                else if (mq.addListener) mq.addListener(onChange);
            } catch (e2) {}
        },

        initModalA11y: function() {
            var prevFocus = null;

            function enhanceModal(modal) {
                if (!modal || modal.getAttribute('data-arx-modal-a11y') === '1') return;
                modal.setAttribute('data-arx-modal-a11y', '1');
                if (!modal.getAttribute('role')) modal.setAttribute('role', 'dialog');
                modal.setAttribute('aria-modal', 'true');
                if (!modal.getAttribute('aria-labelledby')) {
                    var box = modal.querySelector('.modal-box') || modal;
                    var ttl = box.querySelector('h4, h3, .modal-title, .cbi-modal-title');
                    if (ttl && ttl.id) modal.setAttribute('aria-labelledby', ttl.id);
                    else if (ttl) {
                        var nid = 'arx-modal-t-' + String(Math.random()).slice(2, 9);
                        ttl.id = nid;
                        modal.setAttribute('aria-labelledby', nid);
                    }
                }
            }

            function onClassChange(modal) {
                if (modal.classList.contains('active')) {
                    enhanceModal(modal);
                    prevFocus = document.activeElement;
                    var box = modal.querySelector('.modal-box') || modal;
                    var fe = box.querySelector('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
                    if (fe) try { fe.focus(); } catch (e) {}
                } else if (prevFocus && typeof prevFocus.focus === 'function') {
                    try { prevFocus.focus(); } catch (e2) {}
                    prevFocus = null;
                }
            }

            function hookModal(modal) {
                if (!modal || modal.getAttribute('data-arx-modal-hook') === '1') return;
                modal.setAttribute('data-arx-modal-hook', '1');
                enhanceModal(modal);
                if (modal.classList.contains('active')) onClassChange(modal);
                try {
                    var obs = new MutationObserver(function(muts) {
                        muts.forEach(function(mu) {
                            if (mu.type === 'attributes' && mu.attributeName === 'class') onClassChange(modal);
                        });
                    });
                    obs.observe(modal, { attributes: true, attributeFilter: ['class'] });
                } catch (e3) {}
            }

            document.querySelectorAll('.modal').forEach(hookModal);

            try {
                if (!document.body) return;
                var bodyObs = new MutationObserver(function(muts) {
                    muts.forEach(function(mu) {
                        if (!mu.addedNodes || !mu.addedNodes.forEach) return;
                        mu.addedNodes.forEach(function(n) {
                            if (n.nodeType !== 1) return;
                            if (n.classList && n.classList.contains('modal')) hookModal(n);
                            if (n.querySelectorAll) n.querySelectorAll('.modal').forEach(hookModal);
                        });
                    });
                });
                bodyObs.observe(document.body, { childList: true, subtree: true });
            } catch (e4) {}
        },

        getThemeLabel: function(id) {
            for (var i = 0; i < this.THEMES.length; i++) {
                if (this.THEMES[i].id === id) return this.THEMES[i].label;
            }
            return id;
        },

        syncThemeUI: function(theme) {
            this.updateThemePicker(theme);
            this.updateToggleIcon(theme);
        },

        updateThemePicker: function(theme) {
            var opts = document.querySelectorAll('[data-arx-theme]');
            opts.forEach(function(el) {
                var id = el.getAttribute('data-arx-theme');
                var isActive = id === theme;
                el.setAttribute('aria-pressed', isActive ? 'true' : 'false');
                el.classList.toggle('is-active', isActive);
            });
            var btn = document.getElementById('arx-theme-picker-btn');
            if (btn) btn.setAttribute('title', '主题：' + this.getThemeLabel(theme));
        },

        setTheme: function(theme) {
            if (THEME_IDS.indexOf(theme) < 0) theme = 'light';
            document.documentElement.setAttribute('data-theme', theme);
            try {
                localStorage.setItem(LS_THEME, theme);
                localStorage.setItem(LS_THEME_LOCK, '1');
            } catch (e) {}
            this.syncThemeUI(theme);
            this.flashMainContent();
        },

        flashMainContent: function() {
            var mainContent = document.querySelector('.main-inner.main-content') || document.querySelector('.main-content');
            if (mainContent) {
                mainContent.style.transition = 'opacity 0.15s ease';
                mainContent.style.opacity = '0.95';
                setTimeout(function() { mainContent.style.opacity = ''; }, 150);
            }
        },

        updateToggleIcon: function(theme) {
            var btns = document.querySelectorAll('.theme-toggle');
            var icon = '<svg class="arx-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" d="M12 3v3M12 18v3M3 12h3M18 12h3"/><path stroke-linecap="round" d="M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1"/></svg>';
            btns.forEach(function(btn) {
                btn.innerHTML = icon;
            });
        },

        initThemePicker: function() {
            var self = this;
            var menu = document.getElementById('arx-theme-menu');
            var btn = document.getElementById('arx-theme-picker-btn');
            var wrap = document.getElementById('arx-theme-picker');
            if (!menu || !btn || !wrap) return;

            menu.querySelectorAll('[data-arx-theme]').forEach(function(opt) {
                opt.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    var id = opt.getAttribute('data-arx-theme');
                    self.setTheme(id);
                    menu.hidden = true;
                    btn.setAttribute('aria-expanded', 'false');
                });
            });

            btn.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                var open = menu.hidden;
                menu.hidden = !open;
                btn.setAttribute('aria-expanded', open ? 'true' : 'false');
            });

            document.addEventListener('click', function() {
                if (menu.hidden) return;
                menu.hidden = true;
                btn.setAttribute('aria-expanded', 'false');
            });

            wrap.addEventListener('click', function(e) { e.stopPropagation(); });
        },

        toggleTheme: function() {
            var current = document.documentElement.getAttribute('data-theme') || 'light';
            var idx = THEME_IDS.indexOf(current);
            if (idx < 0) idx = 0;
            var next = THEME_IDS[(idx + 1) % THEME_IDS.length];
            this.setTheme(next);
        },

        isNarrowSidebarDesktop: function() {
            try {
                return window.matchMedia('(min-width: 769px)').matches &&
                    document.documentElement.getAttribute('data-arx-sidebar') === 'narrow';
            } catch (e) {
                return false;
            }
        },

        clearSidebarFlyouts: function() {
            document.querySelectorAll('#main-nav .nav-item.flyout-open').forEach(function(n) {
                n.classList.remove('flyout-open');
                var sm = n.querySelector(':scope > .submenu');
                if (sm) sm.style.top = '';
            });
        },

        initSidebarMode: function() {
            var m = 'expanded';
            try {
                var s = localStorage.getItem(LS_SIDEBAR);
                if (s && SIDEBAR_MODES.indexOf(s) >= 0) m = s;
            } catch (e) {}
            document.documentElement.setAttribute('data-arx-sidebar', m);
            this.syncSidebarLayoutUI(m);
        },

        getSidebarMode: function() {
            var m = document.documentElement.getAttribute('data-arx-sidebar');
            if (m && SIDEBAR_MODES.indexOf(m) >= 0) return m;
            return 'expanded';
        },

        setSidebarMode: function(mode) {
            if (SIDEBAR_MODES.indexOf(mode) < 0) mode = 'expanded';
            document.documentElement.setAttribute('data-arx-sidebar', mode);
            try {
                localStorage.setItem(LS_SIDEBAR, mode);
            } catch (e) {}
            this.syncSidebarLayoutUI(mode);
            this.clearSidebarFlyouts();
            var sidebar = document.querySelector('.main-left');
            if (sidebar) sidebar.classList.remove('open');
        },

        cycleSidebarMode: function() {
            var cur = this.getSidebarMode();
            var i = SIDEBAR_MODES.indexOf(cur);
            if (i < 0) i = 0;
            var next = SIDEBAR_MODES[(i + 1) % SIDEBAR_MODES.length];
            this.setSidebarMode(next);
        },

        syncSidebarLayoutUI: function(mode) {
            document.querySelectorAll('[data-arx-sidebar-mode]').forEach(function(el) {
                var m = el.getAttribute('data-arx-sidebar-mode');
                var on = m === mode;
                el.classList.toggle('is-active', on);
                el.setAttribute('aria-pressed', on ? 'true' : 'false');
            });
            var btn = document.getElementById('arx-sidebar-layout-btn');
            if (btn) {
                var labels = { expanded: '展开', narrow: '窄栏', hidden: '隐藏' };
                btn.setAttribute('title', '侧栏：' + (labels[mode] || mode) + '（Ctrl+Shift+B）');
            }
        },

        initSidebarLayoutMenu: function() {
            var self = this;
            var menu = document.getElementById('arx-sidebar-layout-menu');
            var btn = document.getElementById('arx-sidebar-layout-btn');
            var wrap = document.getElementById('arx-sidebar-layout-picker');
            if (!menu || !btn || !wrap) return;

            menu.querySelectorAll('[data-arx-sidebar-mode]').forEach(function(opt) {
                opt.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    var mode = opt.getAttribute('data-arx-sidebar-mode');
                    self.setSidebarMode(mode);
                    menu.hidden = true;
                    btn.setAttribute('aria-expanded', 'false');
                });
            });

            btn.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                var open = menu.hidden;
                menu.hidden = !open;
                btn.setAttribute('aria-expanded', open ? 'true' : 'false');
            });

            document.addEventListener('click', function() {
                if (menu.hidden) return;
                menu.hidden = true;
                btn.setAttribute('aria-expanded', 'false');
            });

            wrap.addEventListener('click', function(e) { e.stopPropagation(); });
        },

        initSidebar: function() {
            var self = this;
            var navItems = document.querySelectorAll('#main-nav .nav-item');

            function syncNavAria() {
                navItems.forEach(function(item) {
                    var link = item.querySelector(':scope > a');
                    var submenu = item.querySelector(':scope > .submenu');
                    if (!link || !submenu) return;
                    if (self.isNarrowSidebarDesktop()) {
                        link.setAttribute('aria-expanded', item.classList.contains('flyout-open') ? 'true' : 'false');
                    } else {
                        link.setAttribute('aria-expanded', item.classList.contains('expanded') ? 'true' : 'false');
                    }
                });
            }

            function closeAllFlyouts() {
                self.clearSidebarFlyouts();
                syncNavAria();
            }

            navItems.forEach(function(item) {
                var link = item.querySelector(':scope > a');
                var submenu = item.querySelector(':scope > .submenu');
                var arrow = item.querySelector('.nav-arrow');

                if (submenu && link) {
                    link.addEventListener('click', function(e) {
                        if (self.isNarrowSidebarDesktop()) {
                            e.preventDefault();
                            e.stopPropagation();
                            var wasOpen = item.classList.contains('flyout-open');
                            navItems.forEach(function(n) {
                                n.classList.remove('flyout-open');
                                var sm = n.querySelector(':scope > .submenu');
                                if (sm) sm.style.top = '';
                            });
                            if (!wasOpen) {
                                item.classList.add('flyout-open');
                                var rect = item.getBoundingClientRect();
                                var top = Math.max(8, Math.min(rect.top, window.innerHeight - 120));
                                submenu.style.top = top + 'px';
                            }
                            syncNavAria();
                            return;
                        }
                        e.preventDefault();
                        var isOpen = item.classList.contains('expanded');
                        navItems.forEach(function(n) { n.classList.remove('expanded'); });
                        if (!isOpen) item.classList.add('expanded');
                        syncNavAria();
                    });

                    if (arrow) {
                        arrow.addEventListener('click', function(e) {
                            if (self.isNarrowSidebarDesktop()) return;
                            e.preventDefault();
                            e.stopPropagation();
                            var isOpen = item.classList.contains('expanded');
                            navItems.forEach(function(n) { n.classList.remove('expanded'); });
                            if (!isOpen) item.classList.add('expanded');
                            syncNavAria();
                        });
                    }
                }

                if (item.querySelector('.submenu .active')) {
                    item.classList.add('expanded');
                }
            });

            syncNavAria();

            document.addEventListener('click', function(e) {
                if (!self.isNarrowSidebarDesktop()) return;
                var inside = false;
                navItems.forEach(function(item) {
                    if (item.contains(e.target)) inside = true;
                });
                if (!inside) closeAllFlyouts();
            });

            var showSideBtn = document.getElementById('arx-show-side') || document.querySelector('.showSide');
            var sidebar = document.querySelector('.main-left');
            if (showSideBtn && sidebar) {
                function syncSideAria() {
                    var open = sidebar.classList.contains('open');
                    showSideBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
                }
                syncSideAria();
                showSideBtn.addEventListener('click', function() {
                    sidebar.classList.toggle('open');
                    syncSideAria();
                });

                document.addEventListener('click', function(e) {
                    if (sidebar.contains(e.target) || showSideBtn.contains(e.target)) return;
                    sidebar.classList.remove('open');
                    syncSideAria();
                });
            }

            try {
                var mq = window.matchMedia('(min-width: 769px)');
                function onViewportChange() {
                    var sb = document.querySelector('.main-left');
                    if (sb) sb.classList.remove('open');
                    var ss = document.getElementById('arx-show-side') || document.querySelector('.showSide');
                    if (ss) ss.setAttribute('aria-expanded', 'false');
                    self.clearSidebarFlyouts();
                    syncNavAria();
                }
                if (mq.addEventListener) {
                    mq.addEventListener('change', onViewportChange);
                } else if (mq.addListener) {
                    mq.addListener(onViewportChange);
                }
            } catch (e2) {}
        },

        filterNav: function(query) {
            query = (query || '').toLowerCase().trim();
            var navContainer = document.getElementById('main-nav') || document.querySelector('.main-left nav');
            if (!navContainer) return;

            var items = navContainer.querySelectorAll(':scope > .nav-item, :scope > ul > .nav-item');
            var sections = navContainer.querySelectorAll(':scope > .nav-section-title, :scope > ul > .nav-section-title');
            var anyVisible = false;

            sections.forEach(function(sec) { sec.style.display = 'none'; });

            items.forEach(function(item) {
                var text = (item.textContent || '').toLowerCase().replace(/\s+/g, ' ').trim();
                var visible = !query || text.indexOf(query) >= 0;
                item.style.display = visible ? '' : 'none';
                if (visible) anyVisible = true;

                var parentSection = null;
                var el = item;
                while (el && el !== navContainer) {
                    el = el.previousElementSibling;
                    if (el && (el.classList.contains('nav-section-title') || el.tagName === 'H3' || el.tagName === 'H4')) {
                        parentSection = el;
                        break;
                    }
                }
                if (visible && parentSection) parentSection.style.display = '';
            });

            var noResultMsg = navContainer.querySelector('.no-nav-results');
            if (!anyVisible && query) {
                if (!noResultMsg) {
                    noResultMsg = document.createElement('div');
                    noResultMsg.className = 'no-nav-results';
                    noResultMsg.style.cssText = 'padding:20px;text-align:center;color:var(--text-muted);font-size:13px;';
                    noResultMsg.textContent = '未找到匹配的导航项';
                    navContainer.appendChild(noResultMsg);
                }
                noResultMsg.style.display = '';
            } else if (noResultMsg) {
                noResultMsg.style.display = 'none';
            }
        },

        initStatusCards: function() {
            if (document.getElementById('cpu-value')) return;
            var cards = document.querySelectorAll('.status-card[data-src]');
            cards.forEach(function(card) {
                ARXTheme.fetchCardData(card);
                setInterval(function() { ARXTheme.fetchCardData(card); }, 15000);
            });
        },

        fetchCardData: function(card) {
            var src = card.getAttribute('data-src');
            if (!src) return;

            var xhr = new XMLHttpRequest();
            xhr.open('GET', src + '?_=' + Date.now(), true);
            xhr.timeout = 5000;
            xhr.onload = function() {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        ARXTheme.updateCard(card, data);
                    } catch (e) {}
                }
            };
            xhr.send();
        },

        updateCard: function(card, data) {
            var valueEl = card.querySelector('.card-value');
            var subEl = card.querySelector('.card-sub');
            var progressEl = card.querySelector('.progress-bar .fill');

            if (valueEl && data.value !== undefined) valueEl.textContent = data.value;
            if (subEl && data.subtitle !== undefined) subEl.innerHTML = data.subtitle;
            if (progressEl && data.percent !== undefined) progressEl.style.width = data.percent + '%';
        },

        getRealtimeUrl: function() {
            var b = document.body;
            if (b && b.getAttribute('data-arx-realtime')) return b.getAttribute('data-arx-realtime');
            return '/cgi-bin/luci/admin/arx-dashboard/realtime';
        },

        initStatusBar: function() {
            if (!document.getElementById('bar-cpu')) return;

            var realtimeUrl = this.getRealtimeUrl();
            var SPARK_N = 30;
            var bufCpu = [];
            var bufMem = [];
            var bufTemp = [];
            for (var si = 0; si < SPARK_N; si++) {
                bufCpu.push(0);
                bufMem.push(0);
                bufTemp.push(0);
            }

            function sparkBandPoints(buf, yLo, yHi) {
                var w = 100;
                var n = buf.length;
                if (n < 2) return '0,' + ((yLo + yHi) / 2) + ' 100,' + ((yLo + yHi) / 2);
                var pad = 0.8;
                var pts = [];
                for (var i = 0; i < n; i++) {
                    var x = (i / (n - 1)) * w;
                    var v = Math.max(0, Math.min(100, buf[i]));
                    var y = yHi - pad - (v / 100) * (yHi - yLo - pad * 2);
                    pts.push(x.toFixed(2) + ',' + y.toFixed(2));
                }
                return pts.join(' ');
            }

            function drawSidebarSpark(cpuPct, memPct, tempC) {
                var elCpu = document.getElementById('arx-spark-cpu');
                var elMem = document.getElementById('arx-spark-mem');
                var elTemp = document.getElementById('arx-spark-temp');
                var wrap = document.getElementById('arx-sidebar-spark-wrap');
                if (!elCpu || !elMem || !elTemp) return;
                bufCpu.shift();
                bufCpu.push(typeof cpuPct === 'number' ? cpuPct : 0);
                bufMem.shift();
                bufMem.push(typeof memPct === 'number' ? memPct : 0);
                var prevTN = bufTemp.length ? bufTemp[bufTemp.length - 1] : 0;
                var tNorm = typeof tempC === 'number' ? Math.max(0, Math.min(100, tempC)) : prevTN;
                bufTemp.shift();
                bufTemp.push(tNorm);
                elCpu.setAttribute('points', sparkBandPoints(bufCpu, 2, 14));
                elMem.setAttribute('points', sparkBandPoints(bufMem, 17, 29));
                elTemp.setAttribute('points', sparkBandPoints(bufTemp, 33, 45));
                if (wrap) {
                    var tShow = typeof tempC === 'number' ? Math.round(tempC) : (tNorm > 0 ? Math.round(tNorm) : '—');
                    wrap.title = 'CPU ' + Math.round(bufCpu[bufCpu.length - 1]) + '% · 内存 ' + Math.round(bufMem[bufMem.length - 1]) + '% · 温度 ' + tShow + (typeof tempC === 'number' || tNorm > 0 ? '°C' : '') + '（约90秒趋势）';
                }
            }

            function apply(d) {
                var wanEl = document.getElementById('bar-wan');
                var wifiEl = document.getElementById('bar-wifi');
                var cpuEl = document.getElementById('bar-cpu');
                var memEl = document.getElementById('bar-mem');
                var tempEl = document.getElementById('bar-temp');

                var cpuPct = null;
                var memPct = null;
                var tempC = null;

                function setVal(el, text) {
                    if (!el) return;
                    var sv = el.querySelector('.status-value');
                    if (sv) sv.textContent = text;
                }

                if (d.interfaces && wanEl) {
                    var wanIface = d.interfaces.find(function(i) { return i.name === 'wan' || i.name === 'pppoe-wan'; });
                    if (wanIface && wanIface.ipv4) {
                        wanEl.className = 'sys-status-item online';
                        setVal(wanEl, wanIface.ipv4.split('.')[3] || '✓');
                    } else {
                        wanEl.className = 'sys-status-item offline';
                        setVal(wanEl, '断开');
                    }
                }

                if (d.interfaces && wifiEl) {
                    var wifiIface = d.interfaces.find(function(i) { return i.name && i.name.match(/^(wlan|ra)/); });
                    if (wifiIface) {
                        wifiEl.className = 'sys-status-item online';
                        setVal(wifiEl, '✓');
                    } else {
                        wifiEl.className = 'sys-status-item warning';
                        setVal(wifiEl, '?');
                    }
                }

                if (d.cpu && cpuEl) {
                    var pct = d.cpu.percent || 0;
                    cpuPct = pct;
                    setVal(cpuEl, pct + '%');
                    cpuEl.className = pct > 80 ? 'sys-status-item danger' : pct > 50 ? 'sys-status-item warning' : 'sys-status-item online';
                }

                if (d.memory && memEl) {
                    var total = d.memory.total || 1;
                    var usedPct = total > 0 ? Math.round(((d.memory.total - d.memory.free) / d.memory.total) * 100) : 0;
                    memPct = usedPct;
                    setVal(memEl, usedPct + '%');
                    memEl.className = usedPct > 85 ? 'sys-status-item danger' : usedPct > 65 ? 'sys-status-item warning' : 'sys-status-item online';
                }

                if (d.temperature && d.temperature.length > 0) {
                    var t = d.temperature[0].temp_c;
                    tempC = t;
                    if (tempEl) {
                        setVal(tempEl, t + '°C');
                        tempEl.className = t > 75 ? 'sys-status-item danger' : t > 60 ? 'sys-status-item warning' : 'sys-status-item online';
                    }
                }

                if (cpuPct !== null || memPct !== null || tempC !== null) {
                    drawSidebarSpark(
                        cpuPct !== null ? cpuPct : bufCpu[bufCpu.length - 1],
                        memPct !== null ? memPct : bufMem[bufMem.length - 1],
                        tempC
                    );
                }
            }

            function pollIntervalMs() {
                return document.visibilityState === 'hidden' ? 15000 : 3000;
            }

            var timerId = null;
            function scheduleTick() {
                if (timerId) clearInterval(timerId);
                timerId = setInterval(tick, pollIntervalMs());
            }

            function tick() {
                var xhr = new XMLHttpRequest();
                xhr.open('GET', realtimeUrl + '?_=' + Date.now(), true);
                xhr.timeout = 8000;
                xhr.onload = function() {
                    if (xhr.status !== 200) return;
                    try {
                        apply(JSON.parse(xhr.responseText));
                    } catch (e) {}
                };
                xhr.send();
            }

            tick();
            scheduleTick();
            document.addEventListener('visibilitychange', scheduleTick);
        },

        initCopyButtons: function() {
            var self = this;
            var SVG_CLIP = '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>';

            function copyText(t) {
                t = (t || '').trim();
                if (!t) return;
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(t).then(function() {
                        self.toast('已复制', 'success');
                    }).catch(function() {
                        fallbackCopy(t);
                    });
                } else {
                    fallbackCopy(t);
                }
            }

            function fallbackCopy(t) {
                var ta = document.createElement('textarea');
                ta.value = t;
                ta.style.position = 'fixed';
                ta.style.left = '-9999px';
                document.body.appendChild(ta);
                ta.select();
                try {
                    if (document.execCommand('copy')) self.toast('已复制', 'success');
                    else self.toast('复制失败', 'danger');
                } catch (e) {
                    self.toast('复制失败', 'danger');
                }
                ta.remove();
            }

            function decorate(el) {
                if (!el || el.getAttribute('data-arx-copy-done') === '1') return;
                var raw = el.getAttribute('data-arx-copy');
                var targetSel = el.getAttribute('data-arx-copy-target');
                var text = raw;
                if (targetSel) {
                    var tgt = document.querySelector(targetSel);
                    if (tgt) text = tgt.textContent || '';
                } else if (!text || text === '') {
                    text = el.textContent || '';
                }
                text = (text || '').replace(/\s+/g, ' ').trim();
                if (!text) return;

                el.setAttribute('data-arx-copy-done', '1');
                el.classList.add('arx-copy-row');

                var btn = document.createElement('button');
                btn.type = 'button';
                btn.className = 'arx-copy-btn';
                btn.setAttribute('aria-label', '复制');
                btn.innerHTML = SVG_CLIP;
                btn.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    var v = el.getAttribute('data-arx-copy');
                    if (v && v.length) copyText(v);
                    else if (targetSel) {
                        var tg = document.querySelector(targetSel);
                        copyText(tg ? tg.textContent : '');
                    } else copyText(el.textContent || '');
                });

                var tag = (el.tagName || '').toUpperCase();
                var inline = el.classList.contains('arx-copy-inline') || tag === 'TD' || tag === 'TH' || tag === 'CODE';
                if (inline) {
                    el.appendChild(btn);
                } else {
                    var wrap = document.createElement('span');
                    wrap.className = 'arx-copy-wrap';
                    while (el.firstChild) wrap.appendChild(el.firstChild);
                    el.appendChild(wrap);
                    el.appendChild(btn);
                }
            }

            function scan() {
                document.querySelectorAll('[data-arx-copy]:not([data-arx-copy-done])').forEach(decorate);
            }

            scan();

            var moTimer = null;
            var mo = new MutationObserver(function() {
                if (moTimer) return;
                moTimer = setTimeout(function() {
                    moTimer = null;
                    scan();
                }, 200);
            });
            mo.observe(document.body, { childList: true, subtree: true });
        },

        initKeyboardShortcuts: function() {
            var searchInput = document.getElementById('nav-search');
            var searchWrap = document.getElementById('sidebar-search-wrap');
            function setSearchFocused(on) {
                if (searchWrap) searchWrap.classList.toggle('is-focused', !!on);
            }
            if (searchInput && searchWrap) {
                searchInput.addEventListener('focus', function() { setSearchFocused(true); });
                searchInput.addEventListener('blur', function() { setSearchFocused(false); });
            }
            document.addEventListener('keydown', function(e) {
                if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
                    // [L6] 输入框聚焦时不拦截，避免与浏览器原生行为冲突
                    var tag = (e.target && e.target.tagName || '').toUpperCase();
                    if (tag === 'INPUT' || tag === 'TEXTAREA' || (e.target && e.target.isContentEditable)) return;
                    e.preventDefault();
                    if (searchInput) {
                        searchInput.focus();
                        setSearchFocused(true);
                    }
                }
                if ((e.ctrlKey || e.metaKey) && e.shiftKey && (e.key === 'B' || e.key === 'b')) {
                    e.preventDefault();
                    ARXTheme.cycleSidebarMode();
                }
            });
        },

        initAnimations: function() {
            var observer = new IntersectionObserver(function(entries) {
                entries.forEach(function(entry) {
                    if (entry.isIntersecting) {
                        entry.target.classList.add('animate-in');
                        observer.unobserve(entry.target);
                    }
                });
            }, { threshold: 0.1 });

            document.querySelectorAll('.status-card, .cbi-section, .mini-card, .login-card, .firmware-card').forEach(function(el) {
                observer.observe(el);
            });
        },

        initTooltips: function() {
            var tooltipEls = document.querySelectorAll('[title]');
            tooltipEls.forEach(function(el) {
                el.addEventListener('mouseenter', function() {
                    var title = el.getAttribute('title');
                    if (!title) return;

                    var tip = document.createElement('div');
                    tip.className = 'arx-tooltip';
                    tip.textContent = title;
                    tip.style.cssText =
                        'position:absolute;z-index:99999;padding:5px 11px;background:var(--bg-card);color:var(--text-primary);' +
                        'font-size:12px;border-radius:6px;white-space:nowrap;pointer-events:none;border:1px solid var(--border-color);' +
                        'box-shadow:var(--shadow-md);backdrop-filter:blur(8px);' +
                        'animation:tooltipIn 0.15s ease-out;';
                    document.body.appendChild(tip);

                    var rect = el.getBoundingClientRect();
                    tip.style.left = (rect.left + rect.width / 2 - tip.offsetWidth / 2) + 'px';
                    tip.style.top = (rect.top - tip.offsetHeight - 8) + 'px';

                    el._tooltip = tip;
                });

                el.addEventListener('mouseleave', function() {
                    if (el._tooltip) {
                        el._tooltip.remove();
                        el._tooltip = null;
                    }
                });
            });
        },

        formatBytes: function(bytes) {
            if (bytes === 0) return '0 B';
            var k = 1024,
                sizes = ['B', 'KB', 'MB', 'GB', 'TB'],
                i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
        },

        formatUptime: function(seconds) {
            if (!seconds || seconds < 60) return '刚刚';
            if (seconds < 3600) return Math.floor(seconds / 60) + '分钟';
            if (seconds < 86400) return Math.floor(seconds / 3600) + '小时';
            return Math.floor(seconds / 86400) + '天';
        },

        escapeHtml: function(text) {
            var div = document.createElement('div');
            div.appendChild(document.createTextNode(text));
            return div.innerHTML;
        },

        fingerprintId: function() {
            var raw = [
                navigator.userAgent || '',
                navigator.platform || '',
                (screen && (screen.width + 'x' + screen.height)) || '',
                (typeof Intl !== 'undefined' && Intl.DateTimeFormat && Intl.DateTimeFormat().resolvedOptions().timeZone) || '',
                navigator.language || ''
            ].join('|');
            var h = 0;
            for (var i = 0; i < raw.length; i++) {
                h = ((h << 5) - h) + raw.charCodeAt(i);
                h |= 0;
            }
            return 'fp_' + (h >>> 0).toString(16);
        },

        loadKnownDevices: function() {
            try {
                var j = localStorage.getItem(LS_DEVICES);
                var a = j ? JSON.parse(j) : [];
                return Array.isArray(a) ? a : [];
            } catch (e) {
                return [];
            }
        },

        saveKnownDevices: function(arr) {
            try {
                localStorage.setItem(LS_DEVICES, JSON.stringify(arr.slice(0, 20)));
            } catch (e) {}
        },

        initTrustedDevices: function() {
            var remember = false;
            var pendingUser = '';
            try {
                remember = sessionStorage.getItem(SS_REMEMBER) === '1';
                pendingUser = sessionStorage.getItem(SS_PENDING_USER) || '';
            } catch (e) {}

            if (remember && pendingUser) {
                var id = this.fingerprintId();
                var list = this.loadKnownDevices();
                var now = Date.now();
                var found = false;
                for (var i = 0; i < list.length; i++) {
                    if (list[i].id === id) {
                        list[i].lastSeen = now;
                        list[i].lastUsername = pendingUser;
                        list[i].label = (navigator.userAgent || '').slice(0, 48);
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    list.push({
                        id: id,
                        lastSeen: now,
                        lastUsername: pendingUser,
                        label: (navigator.userAgent || '').slice(0, 48)
                    });
                }
                list.sort(function(a, b) { return (b.lastSeen || 0) - (a.lastSeen || 0); });
                this.saveKnownDevices(list);
                try {
                    sessionStorage.removeItem(SS_REMEMBER);
                    sessionStorage.removeItem(SS_PENDING_USER);
                } catch (e2) {}
            }

            this.updateSidebarDevicesHint();
        },

        updateSidebarDevicesHint: function() {
            var el = document.getElementById('sidebar-devices-hint');
            if (!el) return;
            var list = this.loadKnownDevices();
            if (!list.length) {
                el.textContent = '';
                el.style.display = 'none';
                return;
            }
            el.style.display = '';
            var maxTs = 0;
            for (var i = 0; i < list.length; i++) {
                if (list[i].lastSeen > maxTs) maxTs = list[i].lastSeen;
            }
            var d = new Date(maxTs);
            var pad = function(n) { return n < 10 ? '0' + n : '' + n; };
            var ds = d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
            el.textContent = '已记录设备 ' + list.length + ' · 最近 ' + ds;
        },

        initPageSkeleton: function() {
            var sk = document.getElementById('arx-page-skeleton');
            try {
                if (sessionStorage.getItem(SS_NAV_SKEL) === '1') {
                    if (sk) sk.classList.add('is-visible');
                    sessionStorage.removeItem(SS_NAV_SKEL);
                }
            } catch (e) {}
            requestAnimationFrame(function() {
                requestAnimationFrame(function() {
                    if (sk) sk.classList.remove('is-visible');
                });
            });
        },

        initNavSkeletonCapture: function() {
            document.addEventListener('click', function(e) {
                var t = e.target;
                if (!t || !t.closest) return;
                var a = t.closest('a[href]');
                if (!a) return;
                if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
                if (a.getAttribute('target') === '_blank' || a.hasAttribute('download')) return;
                var href = a.getAttribute('href') || '';
                if (!href || href.indexOf('javascript:') === 0 || href === '#') return;
                if (href.indexOf('logout') >= 0) return;
                try {
                    var u = new URL(a.href, window.location.href);
                    if (u.origin !== window.location.origin) return;
                } catch (err) {
                    return;
                }
                try {
                    sessionStorage.setItem(SS_NAV_SKEL, '1');
                } catch (e2) {}
            }, true);
        },

        toast: function(message, type) {
            type = type || 'info';
            var bgVar = {
                info: 'var(--primary)',
                success: 'var(--success)',
                warning: 'var(--warning)',
                danger: 'var(--danger)'
            };

            var toast = document.createElement('div');
            toast.style.cssText =
                'position:fixed;top:20px;right:20px;padding:14px 24px;background:' +
                (bgVar[type] || bgVar.info) + ';color:#fff;border-radius:12px;font-size:13.5px;font-weight:500;' +
                'z-index:99999;box-shadow:var(--shadow-lg);animation:fadeInUp 0.35s cubic-bezier(0.22,1,0.36,1);' +
                'max-width:380px;border:1px solid rgba(255,255,255,0.12);font-family:inherit;';
            toast.textContent = message;
            document.body.appendChild(toast);

            setTimeout(function() {
                toast.style.opacity = '0';
                toast.style.transform = 'translateY(-10px)';
                toast.style.transition = 'all 0.3s ease';
                setTimeout(function() { toast.remove(); }, 300);
            }, 3500);
        }
    };

    window.toggleTheme = function() { ARXTheme.toggleTheme(); };
    window.setTheme = function(id) { ARXTheme.setTheme(id); };
    window.filterNav = function(q) { ARXTheme.filterNav(q); };
    window.setSidebarMode = function(mode) { ARXTheme.setSidebarMode(mode); };
    window.cycleSidebarMode = function() { ARXTheme.cycleSidebarMode(); };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() { ARXTheme.init(); });
    } else {
        ARXTheme.init();
    }

    window.ARXTheme = ARXTheme;
})();
