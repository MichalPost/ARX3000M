// ARX3000M — Full Sidebar Definition
// Mirrors header.htm section_defs exactly
window.ARX_SIDEBAR = {
  sections: [
    {
      icon: '📊', label: '状态',
      items: [
        { label: '系统仪表盘',    page: 'dashboard.html' },
        { label: '无线信号强度',  page: 'wifi_rssi.html' },
        { label: 'DNS 解析链',    page: 'dns_chain.html' },
        { label: 'AdGuard+OC',   page: 'adguard_oc.html' },
        { label: '恢复说明',      page: 'recovery.html' },
      ]
    },
    {
      icon: '🌐', label: '网络',
      items: [
        { label: '设备管理',      page: 'netmgr.html' },
        { label: '高级网络',      page: 'network.html' },
        { label: 'WiFi 桥接',    page: 'bridge.html' },
        { label: '无线设置',      page: '#', native: true },
        { label: '接口',          page: '#', native: true },
        { label: 'DHCP/DNS',     page: '#', native: true },
        { label: '防火墙',        page: '#', native: true },
        { label: '路由',          page: '#', native: true },
        { label: 'mwan3',        page: '#', native: true },
        { label: 'SQM 队列',     page: '#', native: true },
      ]
    },
    {
      icon: '✨', label: '服务',
      items: [
        { label: '软件管理',      page: 'software.html' },
        { label: '设置向导',      page: 'wizard.html' },
        { label: 'AdGuard Home', page: '#', native: true },
        { label: 'DDNS',         page: '#', native: true },
        { label: 'ttyd 终端',    page: '#', native: true },
        { label: 'uhttpd',       page: '#', native: true },
        { label: '计划任务',      page: '#', native: true },
        { label: '系统',          page: '#', native: true },
      ]
    },
    {
      icon: '🔒', label: 'VPN',
      items: [
        { label: 'OpenVPN',      page: '#', native: true },
        { label: 'WireGuard',    page: '#', native: true },
        { label: 'FRP 内网穿透', page: '#', native: true },
        { label: 'PassWall',     page: '#', native: true },
        { label: 'Xray',         page: '#', native: true },
      ]
    },
    {
      icon: '💾', label: '存储',
      items: [
        { label: 'Samba',        page: '#', native: true },
        { label: 'NFS',          page: '#', native: true },
        { label: '磁盘管理',      page: '#', native: true },
        { label: 'USB 存储',     page: '#', native: true },
        { label: 'Extroot',      page: '#', native: true },
      ]
    },
    {
      icon: '🚀', label: '代理',
      items: [
        { label: 'OpenClash',    page: '#', native: true },
        { label: 'ShadowSocks',  page: '#', native: true },
        { label: 'V2Ray',        page: '#', native: true },
      ]
    },
    {
      icon: '👥', label: '管控',
      items: [
        { label: '访问控制',      page: '#', native: true },
        { label: '家长控制',      page: '#', native: true },
        { label: '时间控制',      page: '#', native: true },
        { label: 'ARP 绑定',     page: '#', native: true },
        { label: '网络唤醒',      page: '#', native: true },
      ]
    },
    {
      icon: '🔧', label: '工具',
      items: [
        { label: 'WiFi 抓包',    page: 'wificrack.html' },
        { label: 'Evil Twin',    page: 'evil_twin.html' },
        { label: '自定义命令',    page: '#', native: true },
        { label: '固件升级',      page: '#', native: true },
        { label: 'opkg 软件包',  page: '#', native: true },
        { label: 'UPnP',         page: '#', native: true },
        { label: '流量监控',      page: '#', native: true },
      ]
    },
  ],

  render: function(containerId, currentPage) {
    var nav = document.getElementById(containerId);
    if (!nav) return;
    var cur = currentPage || location.pathname.split('/').pop() || 'index.html';

    // give logo icon an id for click-to-toggle
    var logoIcon = document.querySelector('.sb-logo-icon');
    if (logoIcon) logoIcon.id = 'sb-logo-icon';
    var html = '';

    this.sections.forEach(function(sec, si) {
      var secId = 'sb-sec-' + si;
      // check if any item in this section is active
      var secActive = sec.items.some(function(it){ return it.page === cur; });
      html += '<button class="sb-item' + (secActive ? ' open' : '') + '" data-sub="' + secId + '">'
            + '<span class="ico">' + sec.icon + '</span>'
            + '<span class="lbl">' + sec.label + '</span>'
            + '<span class="arr">▾</span></button>';
      html += '<div class="submenu' + (secActive ? ' open' : '') + '" id="' + secId + '">';
      sec.items.forEach(function(it) {
        var isActive = it.page === cur;
        var cls = isActive ? ' class="active"' : '';
        var nativeMark = it.native ? ' <span style="font-size:9px;opacity:.45;vertical-align:middle">↗</span>' : '';
        html += '<a href="' + it.page + '"' + cls + '>' + it.label + nativeMark + '</a>';
      });
      html += '</div>';
    });

    nav.innerHTML = html;

    // bind toggle
    nav.querySelectorAll('.sb-item[data-sub]').forEach(function(btn) {
      btn.addEventListener('click', function() {
        var sub = document.getElementById(btn.dataset.sub);
        if (!sub) return;
        var open = sub.classList.contains('open');
        sub.classList.toggle('open', !open);
        btn.classList.toggle('open', !open);
      });
    });
  }
};
