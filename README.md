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
## Prerequisites
1. Enever.nl [API token](https://enever.nl/prijzenfeeds/)
1. [Docker-Compose (or docker)](https://docs.docker.com/compose/)
1. You need an Azure functions container. More info: [Azure Functions Powershell](https://hub.docker.com/_/microsoft-azure-functions-powershell)
## Azure function app (PowerShell)
This function app will run the script every hour.
Look at the [docker-comopose.yml](docker-compose.yml) for the docker setup that contains:
1. Azure Functions container
1. Azureite (storage account emulator)
## Next steps
1. Download the [Function Apps](Function%20Apps) folder to '/home/{USER}/Function Apps'
1. Download the [.env.azfunc](.env.azfunc) file next to your **docker-compose.yml** file
1. Update the **.env.azfunc** file with its environment variables (like Enever API token, MQTT server, etc)

# Optional
- ElectricSupplier <If you want to apply a filter on energy supplier (ZP e.g.)>
- GasSupplier <If you want to apply a filter on energy supplier (ZP e.g.)>
- EnableLog <Debug loggin>

# Support
This script was not possible without the help of others. Especially about the MQTT part: https://jackgruber.github.io/2019-06-05-ps-mqtt/