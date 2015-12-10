require("L_TelldusLive")

local public_key = "FEHUVEW84RAFR5SP22RABURUPHAFRUNU"
local private_key = "ZUXEVEGA9USTAZEWRETHAQUBUR69U6EF"
local token = "8dd9b45e182e8ed141f93263301ad6be0527e295e"
local token_secret = "938606c765fa040bcc45826f2d60bf7b"

setKeys(public_key, private_key, token, token_secret)

connectionIsValid()

getSensors()
getDevices()

refresh()

