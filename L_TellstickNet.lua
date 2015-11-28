local http=require("socket.http")
local https = require ("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("dkjson")

local public_key = "FEHUVEW84RAFR5SP22RABURUPHAFRUNU"
local private_key = "ZUXEVEGA9USTAZEWRETHAQUBUR69U6EF"
local token = "8dd9b45e182e8ed141f93263301ad6be0527e295e"
local token_secret = "938606c765fa040bcc45826f2d60bf7b"

luup.variable_set("urn:micasaverde-com:serviceId:TellstickNet1","public_key", public_key, lul_device)
luup.variable_set("urn:micasaverde-com:serviceId:TellstickNet1","private_key", private_key, lul_device)
luup.variable_set("urn:micasaverde-com:serviceId:TellstickNet1","token", token, lul_device)
luup.variable_set("urn:micasaverde-com:serviceId:TellstickNet1","token_secret", token_secret, lul_device)

local api_url = "http://api.telldus.com/json"

local function findChild(parentDevice, id)
    for k, v in pairs(luup.devices) do
        if (v.device_num_parent == parentDevice and v.id == id) then
            return k
        end
    end
end

local function getHeaders(url)
	local now=os.time() 
	local nonce = now
	local post_headers="realm=\""..url.."\", oauth_timestamp=\""..now.."\", oauth_version=\"1.0\", oauth_signature_method=\"PLAINTEXT\", oauth_consumer_key=\""..public_key.."\", oauth_token=\""..token.."\", oauth_signature=\""..private_key.."%26"..token_secret.."\", oauth_nonce=\""..nonce.."\""
	return {
			  ["Authorization"] = "OAuth "..post_headers;
		  };
end

local function getDevices()
    local telldus_url= api_url .. "/devices/list?supportedMethods=951"

	local response_body = {}

	local content, status = http.request {
		method = "GET";
		url = telldus_url;
		headers = getHeaders(telldus_url);
		sink = ltn12.sink.table(response_body);
	}
	return JSON.decode(response_body[1])
end

local function getSensors()
    local telldus_url= api_url .. "/sensors/list?includeIgnored=0&includeValues=1"

	local response_body = {}

	local content, status = http.request {
		method = "GET";
		url = telldus_url;
		headers = getHeaders(telldus_url);
		sink = ltn12.sink.table(response_body);
	}
	return JSON.decode(response_body[1])
end

local function addAll(devices, sensors, lul_device)
	child_devices = luup.chdev.start(lul_device);
	for k, d in pairs(devices.device) do
		luup.log("Device : " .. d.id .. " named " .. d.name)
		local state = 0
		if d.state == 1 then
			state = 1
		end
		luup.chdev.append(lul_device, child_devices, d.id, d.name, "", "D_BinaryLight1.xml", "", "urn:upnp-org:serviceId:SwitchPower1,Status=" .. tostring(state), false)
	end

	for k, s in pairs(sensors.sensor) do
		if(s.name) then
			luup.log("Sensor : " .. s.id .. " named " .. s.name)
			if (s.temp) then
				luup.chdev.append(lul_device, child_devices, s.id .. "_temp", s.name .. " temperature", "", "D_TemperatureSensor1.xml", "", "urn:upnp-org:serviceId:TemperatureSensor1,CurrentTemperature=" .. s.temp, false)
			end
			if (s.humidity) then
				luup.chdev.append(lul_device, child_devices, s.id .. "_humidity", s.name .. " humidity", "", "D_HumiditySensor1.xml", "", "urn:micasaverde-com:serviceId:HumiditySensor1,CurrentLevel=" .. s.humidity, false)
			end
		end
	end

	luup.chdev.sync(lul_device, child_devices)
end

function lug_startup(lul_device)
	local devices = getDevices();
	local sensors = getSensors();
	addAll(devices, sensors, lul_device);
end

local function deviceCommand(device_id, command)
	luup.log("Turning device " .. device_id .. " " .. command .. ".")
    local telldus_url=api_url .. "/device/"..command.."?id="..device_id

	local response_body = {}

	local content, status = http.request {
		method = "GET";
		url = telldus_url;
		headers = getHeaders(telldus_url);
		sink = ltn12.sink.table(response_body);
	}
end
