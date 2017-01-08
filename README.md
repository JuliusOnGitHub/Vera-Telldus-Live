# Vera Telldus Live Plugin
Control Telldus (Tellstick, Tellstick duo etc) devices and get sensor values from your VeraEdge/VeraPlus/UI7. It uses the Telldus Live Api to commmunicate with the telldus device.

<img src="http://getvera.com/wp-content/uploads/vera_logo_tm.png" height="100" />
<img src="http://live.telldus.com/img/frameworklive/logoTelldusLive.svg" height="100" />

This is my first attempt at creating a Vera plugin. Hope it works for you.

Copy all the X_TelldusLive.X files into your Vera and create a device in the based on the D_TelldusLive.xml file. 
Add your telldus keys in the settings of the device, validate the connection and refresh the devices.

Note: the devices and sensors are updated by a timer which runs each 2 minuttes. I do not have every kind of device that Telldus supports 
so I have only tested:

* Nexa switch and dimmer
* Nexa pir
* Proove door sensor
* Some temp and humidity sensors

This is just a test implementation. This means that you run this at your own risk.

