if(not lul_device) then
	require("luup")
	lul_device = "12"
end

local http=require("socket.http")
local ltn12 = require("ltn12")
local JSON = require("dkjson")
local bit = require("bit")

--local public_key = ""
--local private_key = ""
--local token = ""
--local token_secret = ""

local public_key = "FEHUVEW84RAFR5SP22RABURUPHAFRUNU"

local private_key = "ZUXEVEGA9USTAZEWRETHAQUBUR69U6EF"

local token = "8dd9b45e182e8ed141f93263301ad6be0527e295e"

local token_secret = "938606c765fa040bcc45826f2d60bf7b"


local TELLDUS_SID = "urn:upnp-telldus-se:serviceId:TelldusApi1"
local HADEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local NETWORK_SID = "urn:micasaverde-com:serviceId:ZWaveNetwork1"
local SECURITY_SID = "urn:micasaverde-com:serviceId:SecuritySensor1"
local SWITCH_SID = "urn:upnp-org:serviceId:SwitchPower1"
local TEMP_SID = "urn:upnp-org:serviceId:TemperatureSensor1"
local HUM_SID = "urn:micasaverde-com:serviceId:HumiditySensor1"
local DIM_SID = "urn:upnp-org:serviceId:Dimming1"

local MOTIONSENSOR_DT = "urn:schemas-micasaverde-com:device:MotionSensor:1"
local DOORSENSOR_DT = "urn:schemas-micasaverde-com:device:DoorSensor:1"
local DIM_DT = "urn:schemas-upnp-org:device:DimmableLight:1"

local REFRESH_INTERVAL = "30"

local api_url = "http://api.telldus.com/json"

local MSG_CLASS = "TelldusLive"
local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1

local TRIPPED = "Tripped"
local ARMED = "Armed"
local ARMEDTRIPPED = "ArmedTripped"
local STATUS = "Status"
local CURRENTLEVEL = "CurrentLevel"
local CURRENTTEMPERATURE = "CurrentTemperature"
local LOADLEVELSTATUS = "LoadLevelStatus"

local TELLSTICK_DIM = 16

local function log(text, level)
    luup.log(string.format("%s: %s", MSG_CLASS, text), (level or 25))
end

local function task(text, mode)
    log("task " .. text)
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
            return v, k
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

local function request(url)
	local response_body = {}

	log("Sending request to url : " .. url)

	local content, status = http.request {
		method = "GET";
		url = url;
		headers = getHeaders(url);
		sink = ltn12.sink.table(response_body);
	}
	log("Response code status : " .. status)
	if(response_body) then
		log("Response body : " .. response_body[1])
	end
	return response_body
end

function getDevices()
    local telldus_url= api_url .. "/devices/list?supportedMethods=951"
	local response_body = request(telldus_url)
	return JSON.decode(response_body[1])
end

function getSensors()
    local telldus_url= api_url .. "/sensors/list?includeIgnored=0&includeValues=1"
	local response_body = request(telldus_url)
	return JSON.decode(response_body[1])
end

local function updateSensors(sensors)
	for k, s in pairs(sensors.sensor) do
		if(s.name) then
			if (s.temp) then
				local device, key = findChild(Telldus_device, s.id .. "_temp")
				if(device) then
					log("Setting sensor " .. s.name .. " temperature to " .. s.temp)
					luup.variable_set(TEMP_SID, CURRENTTEMPERATURE, s.temp, key)
				end
			end
			if (s.humidity) then
				local device, key = findChild(Telldus_device, s.id .. "_humidity")
				if(device) then
					log("Setting sensor " .. s.name .. " humidity to " .. s.temp)
					luup.variable_set(HUM_SID, CURRENTLEVEL, s.humidity, key)
				end
			end
		end
	end
end

local function getVeraState(telldusState)
	if telldusState == 1 then
		return 1
	end
	return 0
end

local function getVeraDimLevel(telldusLevel)
	return telldusLevel * 100 / 255
end
function activityIn(from, to, id)
    local telldus_url= api_url .. "/device/history?id="..id.."&from=" .. from .."&to=" .. to
	local response_body = request(telldus_url)
	local history = JSON.decode(response_body[1])
	return not (next(history.history) == nil)
end
function updateDevices(devices)
	for k, d in pairs(devices.device) do
		log("Device : " .. d.id .. " named " .. d.name .. " updating state to " .. d.state)
		local device, key = findChild(Telldus_device, d.id)
		local state = tostring(getVeraState(d.state))
		if(device) then
			log("Device type : " .. device.device_type)
			if (string.match(device.device_type, "Motion") or string.match(device.device_type, "Door")) then
				log("Setting device " .. d.name .. " Tripped to " .. state)
				luup.variable_set(SECURITY_SID, TRIPPED, state, key)
				local armed, tstamp = luup.variable_get(SECURITY_SID, ARMED, key)
				local armedTripped = luup.variable_get(SECURITY_SID, ARMEDTRIPPED, key)
				if(armed == "1" and armedTripped ~= "0") then
					if(activityIn(tstamp, os.time(), d.id)) then
						luup.variable_set(SECURITY_SID, ARMEDTRIPPED, "1")
					end
				end
			elseif (string.match(device.device_type, "Dim")) then
				local level = 0
				if(d.state == TELLSTICK_DIM) then
					level = tostring(getVeraDimLevel(tonumber(d.statevalue)))
				elseif(d.state == 1) then
					level = 100
				end
				log("Setting device " .. d.name .. " LoadLevelStatus to " .. level)
				luup.variable_set(DIM_SID, LOADLEVELSTATUS, level, key)
			else
				log("Setting device " .. d.name .. " Status to " .. state)
				luup.variable_set(SWITCH_SID, STATUS, state, key)
			end
		end
	end
end

local function getDeviceInfo(id)
    local telldus_url= api_url .. "/device/info?id="..id.."&supportedMethods=951"
	local response_body = request(telldus_url)
	return JSON.decode(response_body[1])
end


function addAll(devices, sensors, lul_device)
	child_devices = luup.chdev.start(lul_device);
	for k, d in pairs(devices.device) do
		log("Device : " .. d.id .. " named " .. d.name .. " supporting methods : " .. tostring(d.methods))
		local deviceinfo = getDeviceInfo(d.id)
		log("Device model : " .. deviceinfo.model)
		if(string.match(deviceinfo.model, "magnet")) then
			log("Device " .. d.name .. " is a magnet")
			luup.chdev.append(lul_device, child_devices, d.id, d.name, "", "D_DoorSensor1.xml", "", "", false)
		elseif (string.match(deviceinfo.model, "pir")) then
			log("Device " .. d.name .. " is a motion sensor")
			luup.chdev.append(lul_device, child_devices, d.id, d.name, "", "D_MotionSensor1.xml", "", "", false)
		else
			log("Device " .. d.name .. " is dimmer or switch")
			if(bit.band(d.methods, TELLSTICK_DIM) > 0) then
				luup.chdev.append(lul_device, child_devices, d.id, d.name, "", "D_DimmableLight1.xml", "", "", false)
			else
				luup.chdev.append(lul_device, child_devices, d.id, d.name, "", "D_BinaryLight1.xml", "", "", false)
			end
		end

	end

	for k, s in pairs(sensors.sensor) do
		if(s.name) then
			log("Sensor : " .. s.id .. " named " .. s.name)
			if (s.temp) then
				luup.chdev.append(lul_device, child_devices, s.id .. "_temp", s.name .. " temperature", "", "D_TemperatureSensor1.xml", "", "", false)
			end
			if (s.humidity) then
				luup.chdev.append(lul_device, child_devices, s.id .. "_humidity", s.name .. " humidity", "", "D_HumiditySensor1.xml", "", false)
			end
		end
	end
	luup.chdev.sync(lul_device, child_devices)
	Telldus_device = lul_device
	updateSensors(sensors)
	updateDevices(devices)
end

function refreshCache()
	log("Telldus timer called...")
	updateSensors(getSensors())
	updateDevices(getDevices())
	luup.call_timer("refreshCache", 1, REFRESH_INTERVAL, "")
	log("Telldus timer exit.")
end

function lug_startup(lul_device)
	log("Entering TelldusLive startup..")
	
	luup.variable_set(TELLDUS_SID,"PublicKey", public_key, lul_device)
	luup.variable_set(TELLDUS_SID,"PrivateKey", private_key, lul_device)
	luup.variable_set(TELLDUS_SID,"Token", token, lul_device)
	luup.variable_set(TELLDUS_SID,"TokenSecret", token_secret, lul_device)

	public_key = luup.variable_get(TELLDUS_SID,"PublicKey", lul_device)
	private_key = luup.variable_get(TELLDUS_SID,"PrivateKey", lul_device)
	token = luup.variable_get(TELLDUS_SID,"Token", lul_device)
	token_secret = luup.variable_get(TELLDUS_SID,"TokenSecret", lul_device)
	
	if (public_key == nil or private_key == nil or token == nil or token_secret == nil) then
        local msg = "Need telldus keys to run."
		log(msg)
        return
    else
		local devices = getDevices()
		local sensors = getSensors()
		addAll(devices, sensors, lul_device);
		luup.call_timer("refreshCache", 1, REFRESH_INTERVAL, "")
	end
end

local function deviceCommand(device_id, command, parameters)
	log("Turning device " .. device_id .. " " .. command .. ".")
    local telldus_url=api_url .. "/device/"..command.."?id="..device_id
	if(parameters) then
		telldus_url = telldus_url .. parameters
	end
	return request(telldus_url)
end

function setDimLevel(device_id, level)
	log("Setting dim level on device " .. device_id .. " to " .. level .. ".")
	local telldusLevel = tonumber(level) * 255 / 100
	return deviceCommand(device_id, "dim", "&level=" .. tostring(telldusLevel))
end

function setTarget()
	if(lul_settings.newTargetValue == "1") then
		deviceCommand(luup.devices[lul_device].id, "turnOn")
	else
		deviceCommand(luup.devices[lul_device].id, "turnOff")
	end

	luup.variable_set(SWITCH_SID, STATUS, lul_settings.newTargetValue, lul_device)

	return true
end

function setLoadLevelTarget()
	if(lul_settings.newLoadlevelTarget == "0") then
		deviceCommand(luup.devices[lul_device].id, "turnOff")
	else
		setDimLevel(luup.devices[lul_device].id, lul_settings.newLoadlevelTarget)
	end

	luup.variable_set(DIM_SID, LOADLEVELSTATUS, lul_settings.newLoadlevelTarget, lul_device)

	return true
end

function setArmed(lul_device, lul_settings)
	luup.variable_set(SECURITY_SID, ARMED, lul_settings.newArmedValue, lul_device)
	if(lul_settings.newArmedValue == "0") then
		luup.variable_set(SECURITY_SID, ARMEDTRIPPED, "0")
	end
	return true
end
