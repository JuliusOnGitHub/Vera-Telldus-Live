--[[
    Emulates the lua luup extensions for testing
]]
luup = {}
local luupvars = {}
local luupwatching = {}
luup.devices = {}
luup.chdev = { }

function luup.chdev.start(deviceId)
	return {}
end

function luup.chdev.sync(deviceId, children)
end

function luup.chdev.append(deviceId, children, id, name, file1, s1, s2, a)
	local newdevice = {}
	newdevice.id = id
	newdevice.name = name
	newdevice.device_num_parent = deviceId
	newdevice.device_type = s1
	table.insert(luup.devices, newdevice)
end

function luup.task(a,b,c,d)
    taskMessage = a
end

function luup.log(msg,lvl)
    if(lvl == nil) then value = "nil" end
    print("LOG "..lvl..": "..msg)
end

function luup.variable_get(serviceId,varName,deviceId)
    key = serviceId..varName..deviceId
    value = luupvars[key]
    if(value == nil) then value = 0 end
    print("variable get: "..key.. " is : "..value)
    return value
end

function luup.variable_set(serviceId,varName,value,deviceId)

    key = serviceId..varName..deviceId
    luupvars[key] = value

    if(value == nil) then value = "nil" end

    print("variable set: "..key..":"..value)
end

function luup.variable_watch(func,service,var,deviceId)
    key = deviceId..service..var
    luupwatching[key] = func
end

function luup.call_action(serviceId,actionName,args,deviceId)

    for k,v in pairs(args) do
        print("pairs "..serviceId..","..k..","..v..","..deviceId)
        luup.variable_set(serviceId,k,v,deviceId)
    end

    -- this allows us to test at least that the call was made as expected
    return {serviceId,actionName,args,deviceId}
end

function luup.call_timer()
    return true;
end
<<<<<<< HEAD
=======

function luup.call_delay()
	return true
end
>>>>>>> origin/master
