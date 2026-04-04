local m, s, o

m = Map("arx-network", translate("防火墙规则管理"),
    translate("配置自定义防火墙规则，控制网络访问权限。"))

s = m:section(TypedSection, "firewall_rule", translate("自定义规则"))
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"

o = s:option(Flag, "enabled", translate("启用"))
o.rmempty = false
o.default = "1"

o = s:option(ListValue, "action", translate("动作"))
o:value("ACCEPT", "允许 (ACCEPT)")
o:value("DROP", "丢弃 (DROP)")
o:value("REJECT", "拒绝 (REJECT)")
o:value("RETURN", "返回 (RETURN)")
o.default = "ACCEPT"

o = s:option(ListValue, "chain", translate("链"))
o:value("input", "INPUT (入站)")
o:value("forward", "FORWARD (转发)")
o:value("output", "OUTPUT (出站)")
o:value("prerouting", "PREROUTING (DNAT)")
o:value("postrouting", "POSTROUTING (SNAT)")
o.default = "forward"

o = s:option(Value, "src_ip", translate("来源 IP / 网段"))
o.datatype = "string"
o.placeholder = "192.168.1.0/24 或留空"

o = s:option(Value, "dst_ip", translate("目标 IP / 网段"))
o.datatype = "string"
o.placeholder = "目标地址或留空"

o = s:option(Value, "src_port", translate("来源端口"))
o.datatype = "portrange"
o.placeholder = "例如: 80,443 或 1000-2000"

o = s:option(Value, "dst_port", translate("目标端口"))
o.datatype = "portrange"
o.placeholder = "目标端口范围"

o = s:option(ListValue, "proto", translate("协议"))
o:value("", "全部")
o:value("tcp", "TCP")
o:value("udp", "UDP")
o:value("icmp", "ICMP")
o:value("tcpudp", "TCP + UDP")

o = s:option(Value, "comment", translate("备注"))

return m
