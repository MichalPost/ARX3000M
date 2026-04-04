local m, s, o

m = Map("arx-network", translate("端口转发规则"),
    translate("配置 NAT 端口转发，将外部访问请求转发到内网指定设备。"))

s = m:section(TypedSection, "portforward", translate("转发规则"))
s.anonymous = true
s.addremove = true
s.template = "cbi/tblsection"

o = s:option(Flag, "enabled", translate("启用"))
o.rmempty = false
o.default = "1"

o = s:option(Value, "name", translate("规则名称"))
o.datatype = "string"
o.placeholder = "例如: Web服务转发"

o = s:option(ListValue, "proto", translate("协议"))
o:value("tcp", "TCP")
o:value("udp", "UDP")
o:value("tcpudp", "TCP + UDP")
o.default = "tcp"

o = s:option(Value, "ext_port", translate("外部端口"))
o.datatype = "portrange"
o.placeholder = "8080 或 1000-2000"

o = s:option(Value, "int_ip", translate("目标内网 IP"))
o.datatype = "ip4addr"
o.placeholder = "192.168.1.100"

o = s:option(Value, "int_port", translate("目标内部端口"))
o.datatype = "portrange"
o.placeholder = "80"

o = s:option(Value, "src_ip", translate("来源 IP (可选)"))
o.datatype = "ip4addr"
o.placeholder = "留空表示允许所有来源"

o = s:option(Value, "comment", translate("备注"))
o.placeholder = "可选备注信息"

return m
