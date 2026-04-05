(function() {
    'use strict';

    function esc(t) { var d = document.createElement('div'); d.appendChild(document.createTextNode(t)); return d.innerHTML; }

    function escAttr(t) {
        if (t == null || t === '') return '';
        return String(t).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
    }

    function setIfaceCopyCell(cell, val, display) {
        if (!cell) return;
        var dis = display != null ? display : val;
        var v = (val && val !== '-') ? val : '';
        var sp = cell.querySelector('span.arx-dash-copy');
        if (sp) {
            sp.textContent = dis || '-';
            if (v) sp.setAttribute('data-arx-copy', v); else sp.removeAttribute('data-arx-copy');
            sp.removeAttribute('data-arx-copy-done');
        } else {
            cell.textContent = dis || '-';
        }
    }

    window.ARX_updateDiskCard = function(disks) {
        if (!disks || !disks.length) return;
        var primary = disks[0];
        for (var i = 0; i < disks.length; i++) {
            if (disks[i].mount === '/overlay') { primary = disks[i]; break; }
        }
        for (var j = 0; j < disks.length; j++) {
            if (disks[j].mount === '/' && primary.mount !== '/overlay') { primary = disks[j]; }
        }
        var d = primary;
        var t = Math.round(d.total / 1048576);
        var u = Math.round(d.used / 1048576);
        var p = typeof d.use_percent === 'number' ? d.use_percent : (t > 0 ? Math.round(u / t * 100) : 0);
        var freeMb = typeof d.free_mb === 'number' ? d.free_mb : Math.round(d.free / 1048576);
        var dv = document.getElementById('disk-value');
        var db = document.getElementById('disk-bar');
        var ds = document.getElementById('disk-sub');
        if (dv) dv.textContent = u + '/' + t;
        if (db) db.style.width = p + '%';
        if (ds) {
            var rs = (d.roles && d.roles.length) ? ' · 用途: ' + d.roles.join(', ') : '';
            ds.textContent = d.mount + ' (' + d.fs_type + ') · 可用:' + freeMb + ' MB' + rs;
        }
        var ov = null;
        for (var ii = 0; ii < disks.length; ii++) {
            if (disks[ii].mount === '/overlay') { ov = disks[ii]; break; }
        }
        if (ov) {
            var op = typeof ov.use_percent === 'number' ? ov.use_percent : (ov.total > 0 ? Math.round(ov.used * 100 / ov.total) : 0);
            var ff = document.getElementById('fw-disk-fill');
            var fp = document.getElementById('fw-disk-pct');
            if (ff) ff.style.width = op + '%';
            if (fp) fp.textContent = op + '%';
        }
        var list = document.getElementById('dash-storage-list');
        if (list) {
            var html = '';
            for (var k = 0; k < disks.length; k++) {
                var x = disks[k];
                var pct = typeof x.use_percent === 'number' ? x.use_percent : Math.round((x.used / x.total) * 100);
                var fmb = typeof x.free_mb === 'number' ? x.free_mb : Math.round(x.free / 1048576);
                var cls = 'storage-row';
                if (x.warn_level === 'danger') cls += ' storage-danger';
                else if (x.warn_level === 'warn') cls += ' storage-warn';
                var rl = (x.roles && x.roles.length) ? (' · ' + x.roles.join(', ')) : '';
                html += '<div class="' + cls + '"><span>' + esc(x.mount) + ' <small>(' + esc(x.fs_type) + ')</small></span><span>' + pct + '% · 余 ' + fmb + ' MB' + esc(rl) + '</span></div>';
            }
            list.innerHTML = html;
        }
        hintDisk(p, freeMb);
    };

    var U = window.ARX_DASH_URLS || {};
    var prevRx = 0, prevTx = 0, prevTime = Date.now();
    var prevIfaceBytes = {};
    var cfg = window.ARX_DASH_CFG || {};
    if (typeof cfg.pollRealtime !== 'number') cfg.pollRealtime = 10;
    if (typeof cfg.pollLogs !== 'number') cfg.pollLogs = 20;
    if (typeof cfg.pollServices !== 'number') cfg.pollServices = 45;
    if (typeof cfg.pollDisk !== 'number') cfg.pollDisk = 90;
    if (typeof cfg.pollHeroDevices !== 'number') cfg.pollHeroDevices = 45;
    cfg.visibilityPause = cfg.visibilityPause === true || cfg.visibilityPause === 'true';
    if (typeof cfg.hiddenMult !== 'number') cfg.hiddenMult = 3;
    if (typeof cfg.deferHeavyMs !== 'number') cfg.deferHeavyMs = 1500;

    var GAUGE_MAX_MBPS = 1000;
    var GAUGE_ARC_LEN = Math.PI * 58;

    function updateSpeedGauge(rxBps, txBps) {
        var wrap = document.getElementById('dash-speed-gauge');
        var arcRx = document.getElementById('dash-gauge-rx-arc');
        var arcTx = document.getElementById('dash-gauge-tx-arc');
        var elRx = document.getElementById('dash-gauge-rx-mbps');
        var elTx = document.getElementById('dash-gauge-tx-mbps');
        var maxLbl = document.getElementById('dash-gauge-max-label');
        if (!arcRx || !arcTx || !elRx || !elTx) return;
        var rxM = Math.max(0, (rxBps * 8) / 1e6);
        var txM = Math.max(0, (txBps * 8) / 1e6);
        var rxPct = Math.min(1, rxM / GAUGE_MAX_MBPS);
        var txPct = Math.min(1, txM / GAUGE_MAX_MBPS);
        arcRx.style.strokeDasharray = GAUGE_ARC_LEN + ' ' + GAUGE_ARC_LEN;
        arcTx.style.strokeDasharray = GAUGE_ARC_LEN + ' ' + GAUGE_ARC_LEN;
        arcRx.style.strokeDashoffset = (GAUGE_ARC_LEN * (1 - rxPct)).toFixed(2);
        arcTx.style.strokeDashoffset = (GAUGE_ARC_LEN * (1 - txPct)).toFixed(2);
        elRx.textContent = rxM.toFixed(2);
        elTx.textContent = txM.toFixed(2);
        if (maxLbl) maxLbl.textContent = String(GAUGE_MAX_MBPS);
        if (wrap) {
            var capped = rxM >= GAUGE_MAX_MBPS * 0.998 || txM >= GAUGE_MAX_MBPS * 0.998;
            wrap.classList.toggle('dash-speed-gauge--capped', capped);
        }
    }

    var SPARK_SEC = 60;
    var cpuSparkBuf = [];
    var netSparkBuf = [];
    for (var _si = 0; _si < SPARK_SEC; _si++) {
        cpuSparkBuf.push(0);
        netSparkBuf.push(0);
    }
    var lastCpuPct = 0;
    var lastNetBps = 0;
    var netSampleReady = false;

    function updateCpuSparkPoly() {
        var lineEl = document.getElementById('cpu-spark-line');
        var fillEl = document.getElementById('cpu-spark-fill');
        if (!lineEl || !fillEl) return;
        var w = 100;
        var h = 32;
        var pad = 2;
        var n = cpuSparkBuf.length;
        if (n < 2) return;
        var pts = [];
        for (var i = 0; i < n; i++) {
            var x = (i / (n - 1)) * w;
            var v = Math.max(0, Math.min(100, cpuSparkBuf[i]));
            var y = pad + (1 - v / 100) * (h - pad * 2);
            pts.push(x.toFixed(2) + ',' + y.toFixed(2));
        }
        var pl = pts.join(' ');
        lineEl.setAttribute('points', pl);
        fillEl.setAttribute('points', '0,' + h + ' ' + pl + ' ' + w + ',' + h);
    }

    function updateNetSparkPoly() {
        var lineEl = document.getElementById('net-spark-line');
        var fillEl = document.getElementById('net-spark-fill');
        if (!lineEl || !fillEl) return;
        var w = 100;
        var h = 32;
        var pad = 2;
        var arr = netSparkBuf;
        var n = arr.length;
        if (n < 2) return;
        var minV = arr[0];
        var maxV = arr[0];
        for (var j = 1; j < n; j++) {
            if (arr[j] < minV) minV = arr[j];
            if (arr[j] > maxV) maxV = arr[j];
        }
        var span = maxV - minV;
        if (span < 1e-9) span = Math.max(maxV, 1);
        var lo = minV;
        var hi = maxV;
        if (span < maxV * 0.08 && maxV > 0) {
            lo = Math.max(0, minV - span * 0.15);
            hi = maxV + span * 0.15;
            span = hi - lo;
            if (span < 1e-9) span = 1;
        }
        var pts = [];
        for (var i = 0; i < n; i++) {
            var x = (i / (n - 1)) * w;
            var yn = (arr[i] - lo) / span;
            if (yn < 0) yn = 0;
            if (yn > 1) yn = 1;
            var y = pad + (1 - yn) * (h - pad * 2);
            pts.push(x.toFixed(2) + ',' + y.toFixed(2));
        }
        var pl = pts.join(' ');
        lineEl.setAttribute('points', pl);
        fillEl.setAttribute('points', '0,' + h + ' ' + pl + ' ' + w + ',' + h);
    }

    setInterval(function() {
        cpuSparkBuf.shift();
        cpuSparkBuf.push(lastCpuPct);
        netSparkBuf.shift();
        netSparkBuf.push(netSampleReady ? lastNetBps : 0);
        updateCpuSparkPoly();
        updateNetSparkPoly();
    }, 1000);

    var pollTimers = [];

    function visMult() {
        if (!cfg.visibilityPause) return 1;
        return document.visibilityState === 'hidden' ? cfg.hiddenMult : 1;
    }

    function setCardHint(id, text, level) {
        var el = document.getElementById(id);
        if (!el) return;
        el.textContent = text || '';
        el.className = 'card-hint' + (level === 'warn' ? ' card-hint--warn' : (level === 'danger' ? ' card-hint--danger' : ''));
    }

    function hintCpu(pct) {
        var t = '瞬时占用，不代表持续负载。';
        var lvl = '';
        if (pct >= 90) { t = '长时间接近 100% 可能影响转发与 Web 响应，建议排查占用进程。'; lvl = 'warn'; }
        else if (pct >= 75) { t = '负载偏高，若持续如此可关注是否有大流量或插件占用 CPU。'; lvl = 'warn'; }
        else { t = '多数情况下 75% 以下较轻松；偶发尖峰属正常。'; }
        setCardHint('cpu-hint', t, lvl);
    }

    function hintMem(total, free) {
        var freePct = total > 0 ? (free / total) * 100 : 0;
        var lvl = '';
        var t = '含缓存可回收；关注「可用」是否过低。';
        if (freePct < 8) { t = '可用内存过低，服务可能被 OOM 终止，建议关闭不必要插件或扩容。'; lvl = 'danger'; }
        else if (freePct < 15) { t = '可用余量偏紧，长期如此可能影响稳定性。'; lvl = 'warn'; }
        setCardHint('mem-hint', t, lvl);
    }

    function hintTemp(c) {
        var lvl = '';
        var t = '不同机型舒适区间不同，仅供参考。';
        if (c >= 85) { t = '持续高于 85°C 建议检查散热与环境通风。'; lvl = 'danger'; }
        else if (c >= 75) { t = '偏高，请关注通风与负载。'; lvl = 'warn'; }
        else if (c < 70) { t = '多数场景下较为舒适。'; }
        setCardHint('temp-hint', t, lvl);
    }

    function hintNet(rxR, txR) {
        var t = '所有非 loopback 接口字节计数聚合后的瞬时速率。';
        var lvl = '';
        var heavy = (rxR + txR) > (8 * 1048576);
        if (heavy) t += ' 长期异常偏高请排查内网终端或外网拉流。';
        setCardHint('net-hint', t, lvl);
    }

    function hintDisk(p, freeMb) {
        var lvl = '';
        var t = 'overlay 空间不足会导致无法写入配置与安装软件。';
        if (p >= 92) { t = '空间极紧，请清理软件包或迁移 overlay。'; lvl = 'danger'; }
        else if (p >= 85) { t = '使用率偏高，建议预留足够空间供升级与日志。'; lvl = 'warn'; }
        else { t = '保持一定余量，避免 opkg 与配置写入失败。'; }
        setCardHint('disk-hint', t, lvl);
    }

    function setHeroSvc(id, on, onLabel, offLabel) {
        var el = document.getElementById(id);
        if (!el) return;
        el.textContent = on ? (onLabel || '运行中') : (offLabel || '未运行');
        el.className = 'dash-hero__value ' + (on ? 'dash-hero__value--ok' : 'dash-hero__value--bad');
    }

    function loadNetworkHealth() {
        if (!U.network_health) return;
        var xhr = new XMLHttpRequest();
        xhr.open('GET', U.network_health + '?_=' + Date.now(), true);
        xhr.timeout = 8000;
        xhr.onload = function() {
            if (xhr.status !== 200) return;
            try {
                var h = JSON.parse(xhr.responseText);
                var dd = h.ddns || {};
                var en = dd.enabled || 0, run = dd.running || 0;
                var hel = document.getElementById('hero-ddns');
                if (hel) {
                    if (en === 0) {
                        hel.textContent = '未启用';
                        hel.className = 'dash-hero__value';
                    } else {
                        hel.textContent = run + '/' + en + ' 运行';
                        hel.className = 'dash-hero__value ' + (run === en ? 'dash-hero__value--ok' : (run > 0 ? 'dash-hero__value--warn' : 'dash-hero__value--bad'));
                    }
                }
                // [H6] 用 network_health 返回的 wan.ipv4 更新 Hero WAN，不再硬编码接口名
                var wan = h.wan || {};
                var wanEl = document.getElementById('hero-wan');
                if (wanEl) {
                    if (wan.up && wan.ipv4) {
                        wanEl.textContent = wan.ipv4;
                        wanEl.className = 'dash-hero__value dash-hero__value--ok';
                    } else {
                        wanEl.textContent = '断开';
                        wanEl.className = 'dash-hero__value dash-hero__value--bad';
                    }
                }
                var dns = h.dns || {}, px = h.proxy || {};
                setHeroSvc('hero-smartdns', dns.smartdns);
                setHeroSvc('hero-adg', dns.adguardhome);
                setHeroSvc('hero-oc', px.openclash);
                setHeroSvc('hero-pw', px.passwall);
            } catch (e) {}
        };
        xhr.send();
    }

    function formatBytes(b) {
        if (!b) return '0 B';
        if (b >= 1073741824) return (b/1073741824).toFixed(2) + ' GB';
        if (b >= 1048576) return (b/1048576).toFixed(1) + ' MB';
        if (b >= 1024) return (b/1024).toFixed(1) + ' KB';
        return b + ' B';
    }

    function formatUptime(s) {
        if (!s || s < 60) return '刚刚';
        var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
        var r = '';
        if (d > 0) r += d + '天 ';
        if (h > 0 || d > 0) r += h + '时 ';
        r += m + '分';
        return r;
    }

    function updateHeroWan(interfaces) {
        // [H6] WAN 状态现在由 loadNetworkHealth() 通过 network_health API 更新（动态读取 UCI WAN 接口名）
        // 此函数保留作为首次渲染前的快速填充，仅在 network_health 尚未返回时使用
        var el = document.getElementById('hero-wan');
        if (!el || !interfaces) return;
        // 只在元素还显示默认占位符时才填充，避免覆盖 loadNetworkHealth 的准确值
        if (el.textContent !== '—') return;
        var wanIface = null;
        for (var i = 0; i < interfaces.length; i++) {
            var nm = interfaces[i].name;
            if (nm === 'wan' || nm === 'pppoe-wan') { wanIface = interfaces[i]; break; }
        }
        if (wanIface && wanIface.ipv4) {
            el.textContent = wanIface.ipv4;
            el.className = 'dash-hero__value dash-hero__value--ok';
        }
    }

    function loadHeroDevices() {
        if (!U.devices_json) return;
        var el = document.getElementById('hero-devices');
        if (!el) return;
        var xhr = new XMLHttpRequest();
        xhr.open('GET', U.devices_json + '?_=' + Date.now(), true);
        xhr.timeout = 6000;
        xhr.onload = function() {
            if (xhr.status !== 200) return;
            try {
                var data = JSON.parse(xhr.responseText);
                var n = typeof data.total === 'number' ? data.total : ((data.devices && data.devices.length) || 0);
                el.textContent = n;
            } catch (e) {}
        };
        xhr.onerror = function() {};
        xhr.send();
    }

    function updateDashboard(data) {
        if (!data) return;

        if (data.hostname) {
            var hh = document.getElementById('hero-hostname');
            if (hh) hh.textContent = data.hostname;
        }
        if (data.interfaces) {
            updateHeroWan(data.interfaces);
        }

        if (data.cpu) {
            var cp = typeof data.cpu.percent === 'number' ? data.cpu.percent : 0;
            lastCpuPct = cp;
            document.getElementById('cpu-value').textContent = data.cpu.percent;
            document.getElementById('cpu-bar').style.width = data.cpu.percent + '%';
            document.getElementById('cpu-sub').textContent = '用户:' + data.cpu.user + ' 系统:' + data.cpu.system;
            hintCpu(data.cpu.percent);
        }
        if (data.memory) {
            var t = Math.round(data.memory.total / 1048576);
            var u = Math.round((data.memory.total - data.memory.free) / 1048576);
            var p = t > 0 ? Math.round(u/t*100) : 0;
            document.getElementById('mem-value').textContent = u + '/' + t;
            document.getElementById('mem-bar').style.width = p + '%';
            document.getElementById('mem-sub').textContent = '可用:' + Math.round(data.memory.free/1048576) + ' MB · 缓存:' + Math.round((data.memory.cached||0)/1048576) + ' MB';
            hintMem(data.memory.total, data.memory.free);
        }
        if (data.interfaces) {
            var tr=0, tt=0;
            for (var i=0;i<data.interfaces.length;i++) { tr+=data.interfaces[i].rx_bytes||0; tt+=data.interfaces[i].tx_bytes||0; }
            var now=Date.now(), dt=(now-prevTime)/1000;
            if (dt>0 && prevTime>0) {
                var rxR=Math.max(0,(tr-prevRx)/dt), txR=Math.max(0,(tt-prevTx)/dt);
                lastNetBps = rxR + txR;
                netSampleReady = true;
                document.getElementById('net-value').innerHTML='<span class="metric-inline">↓'+formatBytes(rxR)+'</span><span class="metric-inline metric-inline--muted">↑'+formatBytes(txR)+'</span>';
                document.getElementById('net-sub').textContent='↓ 总:'+formatBytes(tr)+' · ↑ 总:'+formatBytes(tt);
                var netPct = Math.min(100, Math.round((rxR + txR) / (1048576 * 8) * 100));
                document.getElementById('net-bar').style.width = netPct + '%';
                hintNet(rxR, txR);
                updateSpeedGauge(rxR, txR);
            } else {
                setCardHint('net-hint', '首次采样后将显示各接口聚合速率。', '');
            }
            prevRx=tr; prevTx=tt; prevTime=now;
            updateIfaceTableRealtime(data.interfaces);
        }
        if (data.temperature && data.temperature.length > 0) {
            var t=data.temperature[0];
            document.getElementById('temp-value').textContent=t.temp_c;
            document.getElementById('temp-bar').style.width=Math.min(100,t.temp_c)+'%';
            document.getElementById('temp-sub').textContent=t.name+': '+t.temp_c+'°C';
            hintTemp(t.temp_c);
        }
        if (data.uptime) {
            document.getElementById('uptime-value').textContent=formatUptime(data.uptime);
            document.getElementById('uptime-sub').textContent=new Date(Date.now()-data.uptime*1000).toLocaleString();
        }
    }

    function updateIfaceTableRealtime(interfaces) {
        var tbody = document.querySelector('#iface-table tbody');
        if (!tbody || !interfaces || !interfaces.length) return;
        for (var i = 0; i < interfaces.length; i++) {
            var iface = interfaces[i];
            var name = iface.name;
            if (!name) continue;
            var row = tbody.querySelector('tr[data-iface="' + name.replace(/"/g, '') + '"]');
            if (!row || row.cells.length < 5) continue;
            var total = (iface.rx_bytes || 0) + (iface.tx_bytes || 0);
            var prev = prevIfaceBytes[name];
            if (prev !== undefined && total - prev > 256) {
                row.classList.add('iface-row--flow');
                (function (r) {
                    setTimeout(function () { r.classList.remove('iface-row--flow'); }, 650);
                }(row));
            }
            prevIfaceBytes[name] = total;
            setIfaceCopyCell(row.cells[1], iface.ipv4 || '-', iface.ipv4 || '-');
            setIfaceCopyCell(row.cells[2], (iface.mac || '-').toUpperCase(), (iface.mac || '-').toUpperCase());
            row.cells[3].textContent = formatBytes(iface.rx_bytes || 0);
            row.cells[3].style.color = 'var(--success)';
            row.cells[4].textContent = formatBytes(iface.tx_bytes || 0);
            row.cells[4].style.color = 'var(--primary-light)';
        }
    }

    function loadSystemInfo() {
        if (!U.system_info) return;
        var xhr=new XMLHttpRequest();
        xhr.open('GET', U.system_info, true);
        xhr.onload=function() {
            if (xhr.status===200) try {
                var info=JSON.parse(xhr.responseText);
                var rel = info.release || {};
                var rev = (rel.revision || '').substring(0, 24);
                var fm = document.getElementById('fw-model');
                if (fm) fm.textContent = info.model || '—';
                var platEl = document.getElementById('fw-platform');
                if (platEl) platEl.textContent = (info.system || 'SoC').replace(/\n/g, '').substring(0, 32);
                var fv = document.getElementById('fw-version');
                if (fv) fv.textContent = info.firmware_version || '—';
                var fo = document.getElementById('fw-openwrt');
                if (fo) fo.textContent = rel.description || info.openwrt_description || '—';
                var fk = document.getElementById('fw-kernel');
                if (fk) fk.textContent = info.kernel || '—';
                var fb = document.getElementById('fw-builddate');
                if (fb) fb.textContent = info.build_date || '—';
                var ovf = document.getElementById('fw-overlay-free');
                var otot = info.overlay_total || 0;
                var ofree = info.overlay_free || 0;
                if (ovf && otot > 0) {
                    ovf.textContent = '剩余 ' + formatBytes(ofree) + ' / 共 ' + formatBytes(otot);
                    var ff = document.getElementById('fw-disk-fill');
                    var fp = document.getElementById('fw-disk-pct');
                    var usedPct = Math.min(100, Math.round((otot - ofree) * 100 / otot));
                    if (ff) ff.style.width = usedPct + '%';
                    if (fp) fp.textContent = usedPct + '%';
                } else if (ovf) {
                    ovf.textContent = '剩余空间 —';
                }
                var html='';
                html+='<div class="info-item"><span class="info-label">主机名</span><span class="info-value"><span class="arx-dash-copy arx-copy-inline" data-arx-copy="'+escAttr(info.hostname||'')+'">'+esc(info.hostname||'-')+'</span></span></div>';
                html+='<div class="info-item"><span class="info-label">本地时间</span><span class="info-value"><span class="arx-dash-copy arx-copy-inline" data-arx-copy="'+escAttr(info.localtime||'')+'">'+esc(info.localtime||'-')+'</span></span></div>';
                html+='<div class="info-item"><span class="info-label">目标平台</span><span class="info-value"><code style="font-size:11px;padding:2px 6px;border-radius:4px;background:var(--bg-sidebar);"><span class="arx-dash-copy arx-copy-inline" data-arx-copy="'+escAttr((rel.target||'').replace(/\n/g,''))+'">'+esc((rel.target||'-').replace(/\n/g,''))+'</span></code></span></div>';
                html+='<div class="info-item"><span class="info-label">发行 ID</span><span class="info-value"><span class="arx-dash-copy arx-copy-inline" data-arx-copy="'+escAttr((rel.distribution||'').replace(/\n/g,''))+'">'+esc((rel.distribution||'-').replace(/\n/g,''))+'</span></span></div>';
                html+='<div class="info-item"><span class="info-label">固件修订</span><span class="info-value"><code style="font-size:11px;padding:2px 6px;border-radius:4px;background:var(--bg-sidebar);"><span class="arx-dash-copy arx-copy-inline" data-arx-copy="'+escAttr(rev)+'">'+esc(rev)+'</span></code></span></div>';
                document.getElementById('sysinfo-list').innerHTML=html;
            } catch(e){}
        };
        xhr.send();
    }

    function loadInterfaces() {
        if (!U.network_stats) return;
        var xhr=new XMLHttpRequest();
        xhr.open('GET', U.network_stats + '?_'+Date.now(), true);
        xhr.onload=function() {
            if (xhr.status===200) try {
                var ifs=JSON.parse(xhr.responseText), html='';
                for (var i=0;i<ifs.length;i++) {
                    var f=ifs[i];
                    var nm = String(f.name || '').replace(/"/g, '');
                    var ipv = f.ipv4 || '-';
                    var macv = (f.mac || '-').toUpperCase();
                    html+='<tr data-iface="'+nm+'"><td><strong>'+esc(nm)+'</strong></td>';
                    html+='<td class="font-mono-data"><span class="arx-dash-copy arx-copy-inline" data-arx-copy="'+escAttr(ipv !== '-' ? ipv : '')+'">'+esc(ipv)+'</span></td>';
                    html+='<td class="font-mono-data"><span class="arx-dash-copy arx-copy-inline" data-arx-copy="'+escAttr(macv !== '-' ? macv : '')+'">'+esc(macv)+'</span></td>';
                    html+='<td style="color:var(--success);">'+formatBytes(f.rx_bytes)+'</td>';
                    html+='<td style="color:var(--primary-light);">'+formatBytes(f.tx_bytes)+'</td></tr>';
                }
                if(!html) html='<tr><td colspan="5" style="text-align:center;padding:16px;">无数据</td></tr>';
                document.querySelector('#iface-table tbody').innerHTML=html;
            } catch(e){}
        };
        xhr.send();
    }

    function loadDiskUsage() {
        if (!U.disk_usage) return;
        var xhr=new XMLHttpRequest();
        xhr.open('GET', U.disk_usage, true);
        xhr.onload=function() {
            if (xhr.status===200) try {
                var disks=JSON.parse(xhr.responseText);
                if (window.ARX_updateDiskCard) window.ARX_updateDiskCard(disks);
                else if(disks&&disks.length>0) {
                    var d=disks[0], t=Math.round(d.total/1048576), u=Math.round(d.used/1048576), p=t>0?Math.round(u/t*100):0;
                    document.getElementById('disk-value').textContent=u+'/'+t;
                    document.getElementById('disk-bar').style.width=p+'%';
                    document.getElementById('disk-sub').textContent=d.mount+' ('+d.fs_type+') · 可用:'+Math.round(d.free/1048576)+' MB';
                    hintDisk(p, Math.round(d.free/1048576));
                }
            } catch(e){}
        };
        xhr.send();
    }

    function loadProcesses() {
        if (!U.processes) return;
        var xhr=new XMLHttpRequest();
        xhr.open('GET', U.processes + '?_'+Date.now(), true);
        xhr.timeout=8000;
        xhr.onload=function() {
            if (xhr.status===200) try {
                var procs=JSON.parse(xhr.responseText), list=procs.processes||[], html='';
                for(var i=0;i<Math.min(list.length,10);i++) {
                    var p=list[i];
                    html+='<div class="process-row">';
                    html+='<span class="process-pid">'+p.pid+'</span>';
                    html+='<span class="process-name">'+esc(p.name)+'</span>';
                    html+='<span class="process-cpu">'+p.cpu+'%</span>';
                    html+='<span class="process-mem">'+p.mem+'%</span>';
                    html+='</div>';
                }
                if(!html) html='<p style="padding:16px;text-align:center;color:var(--text-muted);">无进程数据</p>';
                document.getElementById('process-list').innerHTML=html;
            } catch(e){
                document.getElementById('process-list').innerHTML='<p style="padding:16px;text-align:center;color:var(--text-muted);">无法获取进程信息</p>';
            }
        };
        xhr.onerror=function(){ document.getElementById('process-list').innerHTML='<p style="padding:16px;text-align:center;color:var(--text-muted);">获取失败</p>'; };
        xhr.send();
    }

    function loadServices() {
        if (!U.services) return;
        var xhr=new XMLHttpRequest();
        xhr.open('GET', U.services + '?_'+Date.now(), true);
        xhr.timeout=8000;
        xhr.onload=function() {
            if (xhr.status===200) try {
                var svcs=JSON.parse(xhr.responseText), list=svcs.services||[], html='', icons={'firewall':'🛡️','dnsmasq':'🌐','network':'📡','dropbear':'🔑','uhttpd':'🌎','samba4':'📂','nginx':'🌐','adguardhome':'🛡️','cron':'⏰','ddns':'🌍'};
                for(var i=0;i<list.length;i++) {
                    var s=list[i], cls=s.running?'svc-running':'svc-stopped', icon=icons[s.name]||'⚙️', desc=s.description||s.name;
                    html+='<li>';
                    html+='<div class="svc-icon">'+icon+'</div>';
                    html+='<div class="svc-info">';
                    html+='<div class="svc-name">'+esc(s.name)+'</div>';
                    html+='<div class="svc-desc">'+esc(desc)+'</div>';
                    html+='</div>';
                    html+='<span class="svc-status '+cls+'">'+(s.running?'运行中':'已停止')+'</span>';
                    html+='<div class="svc-actions">';
                    if (s.running) {
                        html+='<button type="button" class="svc-btn svc-restart" data-svc="'+escAttr(s.name)+'" title="重启服务">🔄</button>';
                        if (s.name !== 'uhttpd') {
                            html+='<button type="button" class="svc-btn svc-stop" data-svc="'+escAttr(s.name)+'" title="停止服务">⏹</button>';
                        }
                    } else {
                        html+='<button type="button" class="svc-btn svc-start" data-svc="'+escAttr(s.name)+'" title="启动服务">▶</button>';
                    }
                    html+='</div>';
                    html+='</li>';
                }
                if(!html) html='<li style="padding:16px;text-align:center;color:var(--text-muted);">未检测到服务</li>';
                document.getElementById('service-list').innerHTML=html;
                var root = document.getElementById('service-list');
                if (root) {
                    root.querySelectorAll('.svc-btn').forEach(function(btn) {
                        btn.addEventListener('click', function(e) {
                            e.stopPropagation();
                            var svc = this.getAttribute('data-svc');
                            var action = this.classList.contains('svc-restart') ? 'restart' :
                                this.classList.contains('svc-stop') ? 'stop' : 'start';
                            svcAction(svc, action, this);
                        });
                    });
                }
            } catch(e){}
        };
        xhr.send();
    }

    function svcAction(svcName, action, btnEl) {
        if (!btnEl || !U.service_action) return;
        var origText = btnEl.innerHTML;
        btnEl.innerHTML = '...';
        btnEl.style.pointerEvents = 'none';
        var xhr = new XMLHttpRequest();
        xhr.open('POST', U.service_action, true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.timeout = 10000;
        xhr.onload = function() {
            btnEl.style.pointerEvents = '';
            btnEl.innerHTML = origText;
            if (xhr.status !== 200) {
                if (window.ARXTheme && window.ARXTheme.toast) {
                    window.ARXTheme.toast('HTTP ' + xhr.status + ' · ' + svcName, 'danger');
                }
                return;
            }
            try {
                var r = JSON.parse(xhr.responseText);
                if (r.success) {
                    if (window.ARXTheme && window.ARXTheme.toast) {
                        window.ARXTheme.toast(svcName + ' 已' + (action === 'restart' ? '重启' : action === 'stop' ? '停止' : '启动'), 'success');
                    }
                    setTimeout(function() { loadServices(); }, 800);
                } else {
                    if (window.ARXTheme && window.ARXTheme.toast) {
                        window.ARXTheme.toast((r.error || '操作失败') + ': ' + svcName, 'danger');
                    }
                }
            } catch (e) {
                if (window.ARXTheme && window.ARXTheme.toast) {
                    window.ARXTheme.toast('操作失败: ' + svcName, 'danger');
                }
            }
        };
        xhr.onerror = function() {
            btnEl.innerHTML = origText;
            btnEl.style.pointerEvents = '';
            if (window.ARXTheme && window.ARXTheme.toast) {
                window.ARXTheme.toast('网络错误，无法执行操作', 'danger');
            }
        };
        xhr.send(JSON.stringify({ service: svcName, action: action }));
    }

    function loadFirewallStatus() {
        if (!U.fw_status) return;
        var xhr=new XMLHttpRequest();
        xhr.open('GET', U.fw_status + '?_'+Date.now(), true);
        xhr.timeout=5000;
        xhr.onload=function() {
            if (xhr.status===200) try {
                var fw=JSON.parse(xhr.responseText);
                document.getElementById('fw-input').textContent=(fw.input||0)+' 条';
                document.getElementById('fw-forward').textContent=(fw.forward||0)+' 条';
                document.getElementById('fw-nat').textContent=(fw.nat||0)+' 条';
                document.getElementById('fw-sfe').innerHTML=fw.sfe?'<span style="color:var(--success)">✓ 已启用</span>':'<span style="color:var(--text-muted)">未启用</span>';
            } catch(e){}
        };
        xhr.send();
    }

    function loadLogs() {
        if (!U.logs) return;
        var xhr=new XMLHttpRequest();
        xhr.open('GET', U.logs + '?lines=30&_'+Date.now(), true);
        xhr.timeout=5000;
        xhr.onload=function() {
            if (xhr.status===200) try {
                var logs=JSON.parse(xhr.responseText), lines=logs.lines||[], html='';
                for(var i=Math.max(0,lines.length-30);i<lines.length;i++) {
                    var l=lines[i]||'', cls='log-entry';
                    if(l.toLowerCase().match(/error|fail|warn|reject|drop/i)) cls+=' error';
                    else if(l.toLowerCase().match(/notice|info|accept|connect/i)) cls+=' info';
                    html+='<div class="'+cls+'">'+esc(l)+'</div>';
                }
                if(!html) html='<div class="log-entry" style="color:var(--text-muted);">暂无日志</div>';
                document.getElementById('log-viewer').innerHTML=html;
                var lv=document.getElementById('log-viewer');
                lv.scrollTop=lv.scrollHeight;
            } catch(e){ document.getElementById('log-viewer').innerHTML='<div class="log-entry error">日志加载失败</div>'; }
        };
        xhr.send();
    }

    function pollRealtime() {
        if (!U.realtime) return;
        var xhr = new XMLHttpRequest();
        xhr.open('GET', U.realtime + '?_' + Date.now(), true);
        xhr.timeout = 5000;
        xhr.onload = function() {
            if (xhr.status !== 200) return;
            try { updateDashboard(JSON.parse(xhr.responseText)); } catch (e) {}
        };
        xhr.send();
    }

    function clearPollTimers() {
        pollTimers.forEach(function(id) { clearInterval(id); });
        pollTimers = [];
    }

    function schedulePolling() {
        clearPollTimers();
        var m = visMult();
        var rt = Math.max(3000, cfg.pollRealtime * 1000 * m);
        var ld = Math.max(5000, cfg.pollDisk * 1000 * m);
        var ls = Math.max(5000, cfg.pollServices * 1000 * m);
        var ll = Math.max(5000, cfg.pollLogs * 1000 * m);
        var lh = Math.max(5000, cfg.pollHeroDevices * 1000 * m);
        var lnh = Math.max(5000, cfg.pollServices * 1000 * m);
        var lm = Math.max(10000, cfg.pollServices * 2 * 1000 * m);
        pollTimers.push(setInterval(pollRealtime, rt));
        pollTimers.push(setInterval(loadDiskUsage, ld));
        pollTimers.push(setInterval(loadServices, ls));
        pollTimers.push(setInterval(loadLogs, ll));
        pollTimers.push(setInterval(loadHeroDevices, lh));
        pollTimers.push(setInterval(loadNetworkHealth, lnh));
        if (U.mwan_status) pollTimers.push(setInterval(loadMwanStatus, lm));
        if (U.ipv6_status) pollTimers.push(setInterval(loadIpv6Status, lm));
        if (U.mesh_status) pollTimers.push(setInterval(loadMeshStatus, lm));
        if (U.wifi_env) pollTimers.push(setInterval(loadWifiEnv, Math.max(60000, rt * 6)));
    }

    function loadMwanStatus() {
        if (!U.mwan_status) return;
        var el = document.getElementById('hero-mwan');
        if (!el) return;
        var xhr = new XMLHttpRequest();
        xhr.open('GET', U.mwan_status + '?_=' + Date.now(), true);
        xhr.timeout = 6000;
        xhr.onload = function() {
            if (xhr.status !== 200) return;
            try {
                var j = JSON.parse(xhr.responseText);
                if (!j.available) {
                    el.textContent = '—';
                    el.className = 'dash-hero__value';
                    var pol0 = document.getElementById('hero-mwan-pol');
                    if (pol0) pol0.textContent = '—';
                    var sub0 = document.getElementById('hero-mwan-sub');
                    if (sub0) sub0.textContent = '';
                    return;
                }
                el.textContent = j.active_wan || '—';
                el.className = 'dash-hero__value ' + (j.all_up !== false ? 'dash-hero__value--ok' : 'dash-hero__value--warn');
                var sub = document.getElementById('hero-mwan-sub');
                if (sub) sub.textContent = (j.last_event || '').trim();
                var pol = document.getElementById('hero-mwan-pol');
                if (pol) pol.textContent = j.policy || '—';
            } catch (e) {}
        };
        xhr.send();
    }

    function loadIpv6Status() {
        if (!U.ipv6_status) return;
        var box = document.getElementById('dash-ipv6-summary');
        if (!box) return;
        var xhr = new XMLHttpRequest();
        xhr.open('GET', U.ipv6_status + '?_=' + Date.now(), true);
        xhr.timeout = 8000;
        xhr.onload = function() {
            if (xhr.status !== 200) return;
            try {
                var j = JSON.parse(xhr.responseText);
                function tl(st) {
                    if (st === 'ok') return 'traffic-light traffic-light--ok';
                    if (st === 'warn') return 'traffic-light traffic-light--warn';
                    if (st === 'bad') return 'traffic-light traffic-light--bad';
                    return 'traffic-light traffic-light--na';
                }
                var h = '';
                h += '<div class="ipv6-cell"><span class="' + tl(j.pd && j.pd.state) + '"></span>PD 前缀<br><small>' + esc(j.pd && j.pd.detail || '') + '</small></div>';
                h += '<div class="ipv6-cell"><span class="' + tl(j.dhcpv6 && j.dhcpv6.state) + '"></span>LAN DHCPv6/RA<br><small>' + esc(j.dhcpv6 && j.dhcpv6.detail || '') + '</small></div>';
                h += '<div class="ipv6-cell"><span class="' + tl(j.ula && j.ula.state) + '"></span>ULA<br><small>' + esc(j.ula && j.ula.detail || '') + '</small></div>';
                h += '<div class="ipv6-cell"><span class="' + tl(j.firewall6 && j.firewall6.state) + '"></span>IPv6 防火墙(启发式)<br><small>' + esc(j.firewall6 && j.firewall6.detail || '') + '</small></div>';
                box.innerHTML = h;
            } catch (e) {}
        };
        xhr.send();
    }

    function loadMeshStatus() {
        if (!U.mesh_status) return;
        var box = document.getElementById('dash-mesh-summary');
        if (!box) return;
        var xhr = new XMLHttpRequest();
        xhr.open('GET', U.mesh_status + '?_=' + Date.now(), true);
        xhr.timeout = 6000;
        xhr.onload = function() {
            if (xhr.status !== 200) return;
            try {
                var j = JSON.parse(xhr.responseText);
                if (!j.present) {
                    box.innerHTML = '<p class="subpanel-body">未检测到 Mesh / 中继相关配置。</p>';
                    return;
                }
                var h = '<p class="subpanel-body"><strong>' + esc(j.mode || '') + '</strong> · ' + esc(j.summary || '') + '</p>';
                if (j.upstream_ssid) h += '<p class="subpanel-body">上游 SSID: <code>' + esc(j.upstream_ssid) + '</code></p>';
                if (j.signal_dbm) h += '<p class="subpanel-body">信号: ' + esc(j.signal_dbm) + ' dBm</p>';
                if (j.disconnect_hint) h += '<p class="subpanel-body">' + esc(j.disconnect_hint) + '</p>';
                box.innerHTML = h;
            } catch (e) {}
        };
        xhr.send();
    }

    function loadWifiEnv() {
        if (!U.wifi_env) return;
        var box = document.getElementById('dash-wifi-env-body');
        if (!box) return;
        var xhr = new XMLHttpRequest();
        xhr.open('GET', U.wifi_env + '?_=' + Date.now(), true);
        xhr.timeout = 6000;
        xhr.onload = function() {
            if (xhr.status !== 200) return;
            try {
                var j = JSON.parse(xhr.responseText);
                if (!j.interfaces || !j.interfaces.length) {
                    box.innerHTML = '<p>无无线接口信息。</p>';
                    return;
                }
                var h = '';
                for (var i = 0; i < j.interfaces.length; i++) {
                    var w = j.interfaces[i];
                    h += '<p><strong>' + esc(w.ifname || '') + '</strong> · 信道 ' + esc(String(w.channel || '?')) + ' · ' + esc(w.bandwidth || '') + '<br>SSID: ' + esc(w.ssid || '—') + '</p>';
                }
                box.innerHTML = h;
            } catch (e) { box.innerHTML = '<p>加载失败</p>'; }
        };
        xhr.send();
    }

    function runHeavyLoads() {
        loadProcesses();
        loadServices();
        loadFirewallStatus();
        loadLogs();
    }

    function scheduleHeavy() {
        var ms = Math.max(0, cfg.deferHeavyMs);
        if (ms === 0) { runHeavyLoads(); return; }
        var go = function() { runHeavyLoads(); };
        if (window.requestIdleCallback) {
            var t = setTimeout(function() {
                requestIdleCallback(go, { timeout: ms + 2000 });
            }, ms);
            if (t) return;
        }
        setTimeout(go, ms);
    }

    loadSystemInfo();
    loadInterfaces();
    loadDiskUsage();
    scheduleHeavy();
    loadHeroDevices();
    loadNetworkHealth();
    pollRealtime();
    loadMwanStatus();
    loadIpv6Status();
    loadMeshStatus();
    loadWifiEnv();

    schedulePolling();
    document.addEventListener('visibilitychange', function() {
        schedulePolling();
        if (document.visibilityState === 'visible') {
            pollRealtime();
            loadLogs();
            loadNetworkHealth();
            loadHeroDevices();
            loadMwanStatus();
            loadIpv6Status();
            loadMeshStatus();
            loadWifiEnv();
        }
    });

    var qa = document.getElementById('quick-actions-main');
    var qe = document.getElementById('quick-actions-expand');
    if (qa && qe) {
        qe.addEventListener('click', function() {
            var ex = qa.classList.toggle('is-expanded');
            qe.setAttribute('aria-expanded', ex ? 'true' : 'false');
            qe.textContent = ex ? '收起快捷方式' : '更多快捷方式';
        });
    }
})();
