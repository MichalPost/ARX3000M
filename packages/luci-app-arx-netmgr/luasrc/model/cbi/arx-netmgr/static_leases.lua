local m, s, o

m = Map("arx-netmgr", translate("IP-MAC 静态绑定"),
    translate("配置静态 DHCP 租约，将 MAC 地址固定到特定 IP 地址，确保设备每次获取相同的 IP。"))

s = m:section(TypedSection, "static-lease", translate("静态租约列表"))
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"

o = s:option(Flag, "enabled", translate("启用"))
o.rmempty = false
o.default = "1"

o = s:option(Value, "name", translate("设备名称"))
o.datatype = "hostname"
o.placeholder = "例如: MyPhone"

o = s:option(Value, "mac", translate("MAC 地址"))
o.datatype = "macaddr"
o.placeholder = "AA:BB:CC:DD:EE:FF"

o = s:option(Value, "ip", translate("IP 地址"))
o.datatype = "ip4addr"
o.placeholder = "192.168.1.100"

o = s:option(Value, "comment", translate("备注"))
o.datatype = "string"
o.placeholder = "可选备注信息"

return m
