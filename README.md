# DynamicTariff2MQTT
Dynamic Tariff 2 MQTT

# What is it?
This is an Azure Function App that retrieves and stores Energy prices (from Enever.nl) and publish this to MQTT.
Next to the prices it will publish statistics as well like:
- Current price
- Next hour price
- Average price
- Lowest price
- Highest price
- Hours above average
- and more..

This function app is written in PowerShell and does require the dll file 'M2Mqtt.Net.dll' in the modules folder. Downloadble from NuGet (nuget.exe install M2Mqtt -o c:\lib)

# Enever.nl
This function app does retrieve its data from enever.nl. You can easily request an API token to use the pricefeed that is listed there.
https://enever.nl/prijzenfeeds/

# How to use it
You can deploy this Function app within your Azure environment or deploy it as docker container.
You need to define the following variables:
- MQTTserver
- MQTTuser
- MQTTpassword
- EneverAPItoken

Optional:
- ElectricSupplier <If you want to apply a filter on energy supplier (ZP e.g.)>
- GasSupplier <If you want to apply a filter on energy supplier (ZP e.g.)>
- EnableLog <Debug loggin>

# Support
This script was not possible without the help of others. Especially about the MQTT part: https://jackgruber.github.io/2019-06-05-ps-mqtt/