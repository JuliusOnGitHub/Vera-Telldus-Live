if(not lul_device) then -- this is for running testing outside vera
	require("luup")
	lul_device = "12"
	Telldus_device = lul_device
end

local http=require("socket.http")
local ltn12 = require("ltn12")
local JSON = require("dkjson")
local bit = require("bit")

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
local VALIDCONNECTION = "ValidConnection"
local STATUSTEXT = "StatusText"
local REFRESHINTERVAL = "RefreshInterval"
local LASTUPDATED = "LastUpdated"

local PRIVATE_KEY = "PrivateKey"
local PUBLIC_KEY = "PublicKey"
local TOKEN = "Token"
local TOKEN_SECRET = "TokenSecret"

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

function setKeys(pubKey,pk, t, ts) -- for testing
	luup.variable_set(TELLDUS_SID, PUBLIC_KEY, pubKey, Telldus_device)
	luup.variable_set(TELLDUS_SID, PRIVATE_KEY, pk, Telldus_device)
	luup.variable_set(TELLDUS_SID, TOKEN, t, Telldus_device)
	luup.variable_set(TELLDUS_SID, TOKEN_SECRET, ts, Telldus_device)
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
	local public_key = luup.variable_get(TELLDUS_SID, PUBLIC_KEY, Telldus_device)
	local private_key = luup.variable_get(TELLDUS_SID, PRIVATE_KEY, Telldus_device)
	local token = luup.variable_get(TELLDUS_SID, TOKEN, Telldus_device)
	local token_secret = luup.variable_get(TELLDUS_SID, TOKEN_SECRET, Telldus_device)

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

	local success = true

	log("Response code status : " .. status)
	if(response_body and JSON.decode(response_body[1]) ~= nil) then
		log("Response body : " .. response_body[1])
	else
		log("No response object from server")
		success = false
	end

	if(success == true and string.match(status, "200")) then
		task("Connection with telldus successfull.", TASK_SUCCESS)
		luup.variable_set(TELLDUS_SID, STATUSTEXT, "Connection with telldus successfull.",Telldus_device)
		luup.variable_set(TELLDUS_SID,VALIDCONNECTION, "1", Telldus_device)
	else
		task("Error when communicating with telldus server : " .. status, TASK_ERROR_PERM)
		luup.variable_set(TELLDUS_SID, STATUSTEXT, "Error when communicating with telldus server : " .. status,Telldus_device)
		luup.variable_set(TELLDUS_SID,VALIDCONNECTION, "0", Telldus_device)
		success = false
	end

	return response_body, status, success
end

function getDevices()
    local telldus_url= api_url .. "/devices/list?supportedMethods=951"
	local response_body, status, success = request(telldus_url)
	if(success) then
		local devices = JSON.decode(response_body[1])
		if(devices ~= nil) then
			return devices, true
		end
	end
	return { device = {} }, false
end

function getSensors()
    local telldus_url= api_url .. "/sensors/list?includeIgnored=0&includeValues=1"
	local response_body, status, success = request(telldus_url)
	if(success) then
		local sensors = JSON.decode(response_body[1])
		if (sensors ~= nil) then
			return sensors, true
		end
	end
	return { sensor = {} }, false
end

local function updateSensors(sensors)
	for k, s in pairs(sensors.sensor) do
		if(s.name) then
			local timeLimit = os.time() - (60 * 60 * 3)
			if (s.temp) then
				local device, key = findChild(Telldus_device, s.id .. "_temp")
				if(device) then
					if(s.lastUpdated > timeLimit) then -- do not accept old sensor values
						log("Setting sensor " .. s.name .. " temperature to " .. s.temp)
						luup.variable_set(TEMP_SID, CURRENTTEMPERATURE, s.temp, key)
					else
						log("Sensor data to old for " .. s.name .. " with timestamp : " .. s.lastUpdated)
						luup.set_failure(0, device)
					end
				end
			end
			if (s.humidity) then
				local device, key = findChild(Telldus_device, s.id .. "_humidity")
				if(device) then
					if(s.lastUpdated > timeLimit) then -- do not accept old sensor values
						log("Setting sensor " .. s.name .. " humidity to " .. s.humidity)
						luup.variable_set(HUM_SID, CURRENTLEVEL, s.humidity, key)
					else
						log("Sensor data to old for " .. s.name .. " with timestamp : " .. s.lastUpdated)
						luup.set_failure(0, device)
					end
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
	if (history == nil) then
		log("no history found for device")
		return false -- maybe we should trigger the device
	end
	if(next(history.history) ~= nil) then
		log("device has history")
		return true
	end
	log("no history found for device")
	return false;
end

function updateSecurityDevice(key, state, d)
	log("Update security device " .. d.name)
	local armed, tstamp = luup.variable_get(SECURITY_SID, ARMED, key)
	if(armed == "1") then
		log("Device armed...")
		local armedTripped = luup.variable_get(SECURITY_SID, ARMEDTRIPPED, key)
		if(armedTripped == "0") then
			log("and not tripped....checking state")
			if(activityIn(tstamp, os.time(), d.id)) then
				luup.variable_set(SECURITY_SID, ARMEDTRIPPED, "1", key)
				luup.variable_set(SECURITY_SID, TRIPPED, "1", key)
			end
		else
			log("and allready tripped")
		end
	else
		luup.variable_set(SECURITY_SID, TRIPPED, state, key)
	end
end

function updateDimDevice(key, d)
	local level = 0
	if(d.state == TELLSTICK_DIM) then
		level = tostring(getVeraDimLevel(tonumber(d.statevalue)))
	elseif(d.state == 1) then
		level = 100
	end
	log("Setting device " .. d.name .. " LoadLevelStatus to " .. level)
	luup.variable_set(DIM_SID, LOADLEVELSTATUS, level, key)
end

function updateDevices(devices)
	for k, d in pairs(devices.device) do
		log("Device : " .. d.id .. " named " .. d.name .. " updating state to " .. d.state)
		local device, key = findChild(Telldus_device, d.id)
		local state = tostring(getVeraState(d.state))
		if(device) then
			log("Device type : " .. device.device_type)
			if (string.match(device.device_type, "Motion") or string.match(device.device_type, "Door")) then
				log("Setting device " .. d.name .. " security variables")
				updateSecurityDevice(key, state, d)
			elseif (string.match(device.device_type, "Dim")) then
				updateDimDevice(key, d)
			else
				log("Setting device " .. d.name .. " Status to " .. state)
				luup.variable_set(SWITCH_SID, STATUS, state, key)
			end
		end
	end
end

local function getDeviceInfo(id)
    local telldus_url= api_url .. "/device/info?id="..id.."&supportedMethods=951"
	local response_body, status, success = request(telldus_url)
	return JSON.decode(response_body[1])
end

function addAll(devices, sensors, lul_device)
	child_devices = luup.chdev.start(lul_device);
	local counter = 0
	local added = 0
	for k, d in pairs(devices.device) do
		log("Device : " .. d.id .. " named " .. d.name .. " supporting methods : " .. tostring(d.methods))
		local deviceinfo = getDeviceInfo(d.id)
		if(deviceinfo ~= nil) then
			log("Device model : " .. deviceinfo.model)
			if(string.match(deviceinfo.model, "magnet")) then
				log("Device " .. d.name .. " is a magnet")
				luup.chdev.append(lul_device, child_devices, d.id, d.name, "", "D_DoorSensor1.xml", "", "", false)
				added = added + 1
			elseif (string.match(deviceinfo.model, "pir")) then
				log("Device " .. d.name .. " is a motion sensor")
				luup.chdev.append(lul_device, child_devices, d.id, d.name, "", "D_MotionSensor1.xml", "", "", false)
				added = added + 1
			else
				log("Device " .. d.name .. " is dimmer or switch")
				if(bit.band(d.methods, TELLSTICK_DIM) > 0) then
					luup.chdev.append(lul_device, child_devices, d.id, d.name, "", "D_DimmableLight1.xml", "", "", false)
					added = added + 1
				else
					luup.chdev.append(lul_device, child_devices, d.id, d.name, "", "D_BinaryLight1.xml", "", "", false)
					added = added + 1
				end
			end
			counter = counter + 1
		end
	end
	log("Found " .. counter .. " and added " .. added .. " devices.")

	counter = 0
	local tempSensorCount = 0
	local humSensorsCount = 0
	for k, s in pairs(sensors.sensor) do
		if(s.name) then
			log("Sensor : " .. s.id .. " named " .. s.name)
			if (s.temp) then
				luup.chdev.append(lul_device, child_devices, s.id .. "_temp", s.name .. " temperature", "", "D_TemperatureSensor1.xml", "", "", false)
				tempSensorCount = tempSensorCount + 1
			end
			if (s.humidity) then
				luup.chdev.append(lul_device, child_devices, s.id .. "_humidity", s.name .. " humidity", "", "D_HumiditySensor1.xml", "", "", false)
				humSensorsCount = humSensorsCount + 1
			end
		end
		counter = counter + 1
	end
	log("Found " .. counter .. " sensors. Added " .. tempSensorCount .. " temperature sensors. Added " .. humSensorsCount .. " humidity sensors.")
	luup.chdev.sync(lul_device, child_devices)
	updateSensors(sensors)
	updateDevices(devices)
end

function refresh()
	updateSensors(getSensors())
	updateDevices(getDevices())
	local ta = os.date("*t")
	local s = string.format("%d-%02d-%02d %02d:%02d:%02d", ta.year, ta.month, ta.day, ta.hour, ta.min, ta.sec)
	luup.variable_set(TELLDUS_SID, LASTUPDATED, s, Telldus_device)
end

function refreshTrigger()
	log("Telldus timer called...")
	luup.call_delay("refreshTrigger", 120)
	refresh()
	log("Telldus timer exit.")
end

function removeSensorsAndDevices(lul_device)
	task("Removing devices and sensors...", TASK_BUSY)
	child_devices = luup.chdev.start(lul_device);
	luup.chdev.sync(lul_device, child_devices)
	task("Done removing devices and sensors.", TASK_SUCCESS)
end

function refreshSensorsAndDevices(lul_device)
	task("Refreshing devices and sensors...", TASK_BUSY)
	if(connectionIsValid()) then
		local devices = getDevices()
		local sensors = getSensors()
		addAll(devices, sensors, lul_device);
	end
	task("Done refreshing devices and sensors.", TASK_SUCCESS)
end

function areKeysValid()
	local public_key = luup.variable_get(TELLDUS_SID, PUBLIC_KEY, Telldus_device)
	local private_key = luup.variable_get(TELLDUS_SID, PRIVATE_KEY, Telldus_device)
	local token = luup.variable_get(TELLDUS_SID, TOKEN, Telldus_device)
	local token_secret = luup.variable_get(TELLDUS_SID, TOKEN_SECRET, Telldus_device)

	if (public_key == nil or public_key == "" or
		private_key == nil or private_key == "" or
		token == nil or token == "" or
		token_secret == nil or token_secret == "") then
		return false
    end
	return true
end

function init()
	if(luup.variable_get(TELLDUS_SID, REFRESHINTERVAL, Telldus_device) == nil) then
		luup.variable_set(TELLDUS_SID, REFRESHINTERVAL, 120, Telldus_device)
	end

	if(areKeysValid()) then
		return
	end

	if(luup.variable_get(TELLDUS_SID, PUBLIC_KEY, Telldus_device) == nil) then
		luup.variable_set(TELLDUS_SID,"PublicKey", "", Telldus_device)
	end

	if(luup.variable_get(TELLDUS_SID, PRIVATE_KEY, Telldus_device) == nil) then
		luup.variable_set(TELLDUS_SID, PUBLIC_KEY, "", Telldus_device)
	end

	if(luup.variable_get(TELLDUS_SID, TOKEN, Telldus_device) == nil) then
		luup.variable_set(TELLDUS_SID, TOKEN, "", Telldus_device)
	end

	if(luup.variable_get(TELLDUS_SID, TOKEN_SECRET, Telldus_device) == nil) then
		luup.variable_set(TELLDUS_SID, TOKEN_SECRET, "", Telldus_device)
	end



end

function lug_startup(lul_device)
	log("Entering TelldusLive startup..")
	Telldus_device = lul_device
	init(lul_device)
	luup.call_delay("refreshTrigger", luup.variable_get(TELLDUS_SID, REFRESHINTERVAL, Telldus_device))
	if(not areKeysValid()) then
		task("You need to configure the Telldus keys", TASK_ERROR_PERM)
		return false
	end
	return true
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

function setTarget(lul_device, lul_settings)
	if(lul_settings.newTargetValue == "1") then
		deviceCommand(luup.devices[lul_device].id, "turnOn")
	else
		deviceCommand(luup.devices[lul_device].id, "turnOff")
	end

	luup.variable_set(SWITCH_SID, STATUS, lul_settings.newTargetValue, lul_device)

	return true
end

function setLoadLevelTarget(lul_device, lul_settings)
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
		luup.variable_set(SECURITY_SID, ARMEDTRIPPED, "0", lul_device)
	else
		luup.variable_set(SECURITY_SID, TRIPPED, "0", lul_device)
	end
	return true
end

function testConnection()
	task("Testing connection to Telldus Live...", TASK_BUSY)
	if(connectionIsValid()) then
		task("Connected with Telldus Live successfully.", TASK_SUCCESS)
	else
		task("Could not connect, please check keys and that Telldus Live is reachable.", TASK_ERROR)
	end
end

function lastConnectionWasValid()
	return luup.variable_get(TELLDUS_SID,VALIDCONNECTION, lul_device) == "1"
end

function connectionIsValid()
	if(areKeysValid()) then
		local body, status = request(api_url .. "/clients/list")
		return string.match(status, "200")
	end
	return false
end
