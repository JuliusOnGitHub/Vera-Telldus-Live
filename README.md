# VeraTelldusLive
Control Telldus devices and get sensor values.

This is my first attempt at creating a Vera plugin. Hope it works for you.

Copy all the X_TelldusLive.X files into your Vera and create a device in the based on the D_TelldusLive.xml file. 
Add your telldus keys in the settings of the device, validate the connection and refresh the devices.

Note: the devices and sensors are updated by a timer which runs each 30 seconds. I do not have every kind of device that Telldus supports 
so I have only tested:

* Nexa switch and dimmer
* Nexa pir
* Proove door sensor
* Some temp and humidiy sensors

