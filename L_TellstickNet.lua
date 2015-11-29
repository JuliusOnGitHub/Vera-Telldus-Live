local http=require("socket.http")
local https = require ("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("dkjson")

local public_key = "FEHUVEW84RAFR5SP22RABURUPHAFRUNU"
local private_key = "ZUXEVEGA9USTAZEWRETHAQUBUR69U6EF"
local token = "8dd9b45e182e8ed141f93263301ad6be0527e295e"
local token_secret = "938606c765fa040bcc45826f2d60bf7b"

luup.variable_set("urn:upnp-julius-com:serviceId:telldusapi","PublicKey", public_key, lul_device)
luup.variable_set("urn:upnp-julius-com:serviceId:telldusapi","PrivateKey", private_key, lul_device)
luup.variable_set("urn:upnp-julius-com:serviceId:telldusapi","Token", token, lul_device)
luup.variable_set("urn:upnp-julius-com:serviceId:telldusapi","TokenSecret", token_secret, lul_device)

local HADEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local NETWORK_SID = "urn:micasaverde-com:serviceId:ZWaveNetwork1"

local api_url = "http://api.telldus.com/json"

local MSG_CLASS = "TelldusLive"
local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1

local function log(text, level)
    luup.log(string.format("%s: %s", MSG_CLASS, text), (level or 50))
end

local function task(text, mode)
    luup.log("task " .. text)
    if (mode == TASK_ERROR_PERM) then
        taskHandle = luup.task(text, TASK_ERROR, MSG_CLASS, taskHandle)
    else
        taskHandle = luup.task(text, mode, MSG_CLASS, taskHandle)

        -- Clear the previous error, since they're all transient
        if (mode ~= TASK_SUCCESS) then
            luup.call_delay("clearTask", 30, "", false)
        end
    end
end

function clearTask()
    task("Clearing...", TASK_SUCCESS)
end

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

local function updateSensors(sensors)
	for k, s in pairs(sensors.sensor) do
		if(s.name) then
			if (s.temp) then
				local device = findChild(Telldus_device, s.id .. "_temp")
				if(device) then
					luup.log("Setting sensor " .. s.name .. " temperature to " .. s.temp)
					luup.variable_set("urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", s.temp, device)
				end
			end
			if (s.humidity) then
				local device = findChild(Telldus_device, s.id .. "_humidity")
				if(device) then
					luup.log("Setting sensor " .. s.name .. " humidity to " .. s.temp)
					luup.variable_set("urn:micasaverde-com:serviceId:HumiditySensor1", "CurrentLevel", s.humidity, device)
				end
			end
		end
	end
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
				luup.chdev.append(lul_device, child_devices, s.id .. "_temp", s.name .. " temperature", "", "D_TemperatureSensor1.xml", "", "", false)
			end
			if (s.humidity) then
				luup.chdev.append(lul_device, child_devices, s.id .. "_humidity", s.name .. " humidity", "", "D_HumiditySensor1.xml", "", "", false)
			end
		end
	end
	luup.chdev.sync(lul_device, child_devices)
	Telldus_device = lul_device
	updateSensors(sensors)
end

function refreshCache()
--	task("Telldus sensor sync start", TASK_BUSY)	
--	task("Telldus sensor sync start successful.",TASK_SUCCESS)
	luup.log("Telldus timer called...")
	updateSensors(getSensors())
	luup.call_timer("refreshCache", 1, "30", "")	
	luup.log("Telldus timer exit.")
end

function lug_startup(lul_device)
	local devices = getDevices()
	local sensors = getSensors()
	addAll(devices, sensors, lul_device);
	luup.call_timer("refreshCache", 1, "30", "")	
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
