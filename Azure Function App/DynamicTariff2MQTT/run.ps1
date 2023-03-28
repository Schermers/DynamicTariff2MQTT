using namespace System.Net

# Input bindings are passed in via param block.
param($Timer)

# Write to the Azure Functions log stream.
$retainData = 1 # 0 = False, 1 = true

# Define script var to its name
$script = $MyInvocation.MyCommand.Name

# Write Log function
function Write-Log {
    param(
        [string]$value
    )
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm') | $($value)"
    # Write log to file
    if($env:EnableLog) {
        [pscustomobject]@{
            Date = (Get-Date -format 'yyyy-MM-dd')
            Time = (Get-Date -format 'HH:mm:ss')
            Script = $script
            ScriptVersion = $scriptVersion
            Event = $value
        } | Export-Csv -Path ".\DynamicTariff2MQTT\Log\DynamicTariff2MQTT_$(Get-Date -Format "yyyy-MM-dd").csv" -Delimiter ';' -Append -Encoding utf8 -NoTypeInformation
    }
}
# Set timezone to West Europe
$timeZone = 'W. Europe Standard Time'
if((Get-TimeZone).Id -ne $timeZone) {
    Write-Log "Current timezone: $((Get-TimeZone).Id), will be changed to $timeZone"
    # Change timezone to West europe
    Set-TimeZone -Id $timeZone
}
function Get-CurrentHourPrice {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    
    # Get current price
    return ($energyData | Where-Object Date -eq (Get-Date -Minute 0 -Second -0 -format 'yyyy-MM-dd HH:mm:ss'))."$energySupplierName"
}
function Get-NextHourPrice {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    # Get next hour price
    return ($energyData | Where-Object Date -eq (Get-Date (Get-Date -Minute 0 -Second -0).AddHours(1) -format 'yyyy-MM-dd HH:mm:ss'))."$energySupplierName"
}
function Get-AverageHourPrice {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        $energyData,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    # Get Average Price, round to 6 digits (the same as source)
    return [math]::Round(($energyData."$energySupplierName" | Measure-Object -Average).Average,6)
}
function Get-LowestHourPriceWholeDay {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    # Was testing another method to determine lowest price, disadvantage: it only returns 1 row (even of there are multple rows with the same lowest price)
    #$energyData[[array]::indexof($($energyData."$energySupplierName"),"$(($energyData."$energySupplierName" | Measure-Object -Minimum).Minimum)")]

    # Determine lowest price, return that entry (Date + Price)
    return ($energyData | Select-Object Date,"$energySupplierName") | Where-Object "$energySupplierName" -eq ($energyData."$energySupplierName" | Measure-Object -Minimum).Minimum
}
function Get-HighestHourPriceWholeDay {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    # Determine highest price(s), return that entry (Date + Price)
    return ($energyData | Select-Object Date,"$energySupplierName") | Where-Object "$energySupplierName" -eq ($energyData."$energySupplierName" | Measure-Object -Maximum).Maximum
}
function Get-LowestHourPriceFuture {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    # Filter future data
    $futureEnergyData = $energyData | Select-Object Date,"$energySupplierName" | Where-Object { $_.Date -ge $(Get-Date -Minute 0 -Second -0)}
    # Return lowest price entry(s) (Date + Price)
    return $futureEnergyData | Where-Object "$energySupplierName" -eq ($futureEnergyData."$energySupplierName" | Measure-Object -Minimum).Minimum
}
function Get-HighestHourPriceFuture {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    # Filter future data
    $futureEnergyData = $energyData | Select-Object Date,"$energySupplierName" | Where-Object {$_.Date -ge $(Get-Date -Minute 0 -Second -0).AddHours(-1)}
    # Return highest price entry(s) (Date + Price)
    return $futureEnergyData | Where-Object "$energySupplierName" -eq ($futureEnergyData."$energySupplierName" | Measure-Object -Maximum).Maximum
}

function Get-HoursBelowAverage {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    # Select all prices below average price
    return $energyData | Select-Object Date,"$energySupplierName" |  Where-Object "$energySupplierName" -lt ($energyData."$energySupplierName" | Measure-Object -Average).Average
}
function Get-HoursAboveAverage {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    # Select all prices above average price
    return $energyData | Select-Object Date,"$energySupplierName" |  Where-Object "$energySupplierName" -ge ($energyData."$energySupplierName" | Measure-Object -Average).Average
}
# Function to collect all the statistics and return a hashtable
function Get-Statistics {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data today as array")]
        [array]$energyDataToday,
        [Parameter(Mandatory=$false,HelpMessage="Energy data tomorrow as array")]
        [array]$energyDataTomorrow,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName,
        [Parameter(Mandatory=$True,HelpMessage="Eletric or Gas")]
        [ValidateSet("electric", "gas")]
        [string]$energyType
    )
    switch($energyType) {
        'electric' {
            # If data of tomorrow is available
            if($energyDataTomorrow) {
                # Combine data
                $energyDataCombined = ($energyDataToday+$energyDataTomorrow)
            }
            else {
                # Only use today's data
                $energyDataCombined = $energyDataToday
            }

            # Get lowest & highest prices of today
            $lowestHourToday = (Get-LowestHourPriceWholeDay -energyData ($energyDataToday) -energySupplierName $energySupplierName)
            $highestHourToday = (Get-HighestHourPriceWholeDay -energyData ($energyDataToday) -energySupplierName $energySupplierName)
            
            # Get lowest & highest prices of the future    
            $lowestHourFuture = (Get-LowestHourPriceFuture -energyData ($energyDataCombined) -energySupplierName $energySupplierName)
            $highestHourFuture = (Get-HighestHourPriceFuture -energyData ($energyDataCombined) -energySupplierName $energySupplierName)
            
            [pscustomobject]$statisticsData = @{
                Today = @{
                    price_current = (Get-CurrentHourPrice -energyData $energyDataToday -energySupplierName $energySupplierName)
                    price_next = (Get-NextHourPrice -energyData ($energyDataCombined) -energySupplierName $energySupplierName)
                    price_average = (Get-AverageHourPrice -energyData $energyDataToday -energySupplierName $energySupplierName)
                    price_lowest = $lowestHourToday[0]."$energySupplierName"
                    price_highest = $highestHourToday[0]."$energySupplierName"
                    hours_lowest = ($lowestHourToday | ConvertTo-Json)
                    hours_highest = ($highestHourToday | ConvertTo-Json)
                    price_future_lowest = $lowestHourFuture[0]."$energySupplierName"
                    price_future_highest = $highestHourFuture[0]."$energySupplierName"
                    hours_future_lowest = ($lowestHourFuture | ConvertTo-Json)
                    hours_future_highest = ($highestHourFuture | ConvertTo-Json)
                    hours_below_average = (Get-HoursBelowAverage -energyData $energyDataToday -energySupplierName $energySupplierName | ConvertTo-Json)
                    hours_above_average = (Get-HoursAboveAverage -energyData $energyDataToday -energySupplierName $energySupplierName | ConvertTo-Json)
                }
            }

            # If data of tomorrow is available
            if($energyDataTomorrow) { 
                # Get lowest & highest prices of tomorrow
                $lowestHourTomorrow = (Get-LowestHourPriceWholeDay -energyData ($energyDataTomorrow) -energySupplierName $energySupplierName)
                $highestHourTomorrow = (Get-HighestHourPriceWholeDay -energyData ($energyDataTomorrow) -energySupplierName $energySupplierName)

                [pscustomobject]$statisticsDataTomorrow = @{
                    Tomorrow = @{
                        price_average = Get-AverageHourPrice -energyData $energyDataTomorrow -energySupplierName $energySupplierName
                        price_lowest = $lowestHourTomorrow[0]."$energySupplierName"
                        price_highest = $highestHourTomorrow[0]."$energySupplierName"
                        hours_lowest = ($lowestHourTomorrow | ConvertTo-Json)
                        hours_highest = ($highestHourTomorrow | ConvertTo-Json)
                        hours_below_average = (Get-HoursBelowAverage -energyData $energyDataTomorrow -energySupplierName $energySupplierName | ConvertTo-Json)
                        hours_above_average = (Get-HoursAboveAverage -energyData $energyDataTomorrow -energySupplierName $energySupplierName | ConvertTo-Json)
                    }
                }    
                # Combine data
                $statisticsData += $statisticsDataTomorrow
            }
        }
        'gas' {
            
            [pscustomobject]$statisticsData = @{
                Today = @{
                    price_current = $energyDataToday[0]."$energySupplierName"
                }
            }
            # return current statistics
            if($energyDataToday.length -gt 1) {
                Write-Log "Get-Statistics | Gas price of tomorrow is available, add it to the statistics"
                [pscustomobject]$statisticsDataTomorrow = @{
                    Tomorrow = @{
                        price = $energyDataToday[1]."$energySupplierName"
                    }
                }
                $statisticsData += $statisticsDataTomorrow
            }
        }
    }
    # return data
    return $statisticsData
}
# Function to publish the statistics results to MQTT
function Publish-Statistics {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [pscustomobject]$statisticsData,
        [Parameter(Mandatory=$True,HelpMessage="Eletric or Gas")]
        [ValidateSet("electric", "gas")]
        [string]$energyType,
        [Parameter(Mandatory=$True,HelpMessage="Today or tomorrow")]
        [ValidateSet("Today", "Tomorrow")]
        [string]$day,
        [Parameter(Mandatory=$True,HelpMessage="Name of energy supplier")]
        [string]$energySupplierName
    )
    
    foreach($key in $statisticsData.Keys) {
        Write-Output "$day | $key"
        # Publish message
        $MQTTobject.Publish("dynamictariff/$energyType/statistics/$day/$energySupplierName/$key", [System.Text.Encoding]::UTF8.GetBytes($($statisticsData[$key])), 0, $retainData) 
    }
}
# Function to publish the raw statistics results to MQTT
function Publish-RawStatistics {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [pscustomobject]$totalStatisticsData
    )

    # Convert data to JSON
    $rawElectricData = $totalStatisticsData.electric | ConvertTo-Json -Depth 20
    $rawGasData = $totalStatisticsData.gas | ConvertTo-Json -Depth 20

    # Publish raw statistics
    $MQTTobject.Publish("dynamictariff/electric/statistics/rawData", [System.Text.Encoding]::UTF8.GetBytes($rawElectricData), 0, $retainData) 
    $MQTTobject.Publish("dynamictariff/gas/statistics/rawData", [System.Text.Encoding]::UTF8.GetBytes($rawGasData), 0, $retainData) 
}
# Function to publish prices to MQTT
function Publish-RawPrices {
    param (
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Eletric or Gas")]
        [ValidateSet("electric", "gas")]
        [string]$energyType,
        [Parameter(Mandatory=$True,HelpMessage="Today or tomorrow")]
        [ValidateSet("Today", "Tomorrow")]
        [string]$day
    )

    # Convert data to JSON
    $rawData = $energyData | ConvertTo-Json -Depth 20

    # Publish raw data
    $MQTTobject.Publish("dynamictariff/$energyType/$day/rawData", [System.Text.Encoding]::UTF8.GetBytes($rawData), 0, $retainData) 
}
# Convert the JSON input (string) to Date and Float objects (requered to do correct calculations and to avoid weird stuff)
function Convert-DataArray {
    param(
        [Parameter(Mandatory=$True,HelpMessage="Old data array")]
        [array]$DataArray
    )
    
    # Create new array
    $newDataArray = @()
    # Replace each string for a Date object
    foreach($row in $DataArray) {
        # Create new PS object
        $newDataRow = New-Object -TypeName PSObject
        # Loop through each column
        foreach($column in ($row | Get-Member -MemberType NoteProperty)) {
            # It is either a Date (Get-Date) or a price value
            switch($column.Name) {
                "datum" {
                    Add-Member -InputObject $newDataRow -MemberType NoteProperty -Name Date -Value $(Get-Date $row.datum -format 'yyyy-MM-dd HH:mm:ss')
                }
                "prijs" {
                    Add-Member -InputObject $newDataRow -MemberType NoteProperty -Name Exchange -Value $([float]$row."$($column.Name)")
                }
                default {
                    # Replace each string for a float object
                    Add-Member -InputObject $newDataRow -MemberType NoteProperty -Name ($column.Name).replace("prijs","") -Value $([float]$row."$($column.Name)")
                }
            }
        }
        # Add row to array
        $newDataArray += $newDataRow
    }
    # Return array
    return $newDataArray
}
# function OLD-Convert-DataArray {
#     param(
#         [Parameter(Mandatory=$True,HelpMessage="Old data array")]
#         [array]$DataArray
#     )
#     # Loop through each column
#     foreach($column in ($DataArray | Get-Member -MemberType NoteProperty)) {
#         # It is either a Date (Get-Date) or a price value
#         switch($column.Name) {
#             "Date" {
#                 # Replace each string for a Date object
#                 foreach($row in $DataArray) {
#                     $DataArray[[array]::indexof($DataArray."$($column.Name)",$row."$($column.Name)")]."$($column.Name)" = Get-Date $row.Date -format 'yyyy-MM-dd HH:mm:ss'
#                 }
#             }
#             default {
#                 # Replace each string for a float object
#                 foreach($row in $DataArray) {
#                     $DataArray[[array]::indexof($DataArray."$($column.Name)",$row."$($column.Name)")]."$($column.Name)" = [float]$row."$($column.Name)"
#                 }
#             }
#         }
#     }
# }
function Get-DataValid {
    param(
        [Parameter(Mandatory=$True,HelpMessage="Energy data as array")]
        [array]$energyData,
        [Parameter(Mandatory=$True,HelpMessage="Eletric or Gas")]
        [ValidateSet("electric", "gas")]
        [string]$energyType,
        [Parameter(Mandatory=$True,HelpMessage="Today or tomorrow")]
        [ValidateSet("Today", "Tomorrow")]
        [string]$day
    )
    # Declare variable
    [bool]$validData = $false

    # Check based on energytype
    switch($energyType) {
        'electric'{
            switch($day) {
                'Today' {
                    # Compare with today
                    $dateToCheck = $(Get-Date -format "yyyy-MM-dd")
                }
                'Tomorrow' {
                    # Compare with tomorrow
                    $dateToCheck = $(Get-Date -Hour 0 (Get-Date).AddDays(1) -format "yyyy-MM-dd")
                }
            }

            Write-Log "Get-DataValid | Check if data ($(Get-Date $energyData[0].Date -format "yyyy-MM-dd")) is up-to-date (I.e. -eq to $dateToCheck)"
            # Verify if data is up to date
            if($(Get-Date $energyData[0].Date -format "yyyy-MM-dd") -eq $dateToCheck) {
                Write-Log "Get-DataValid | Data is valid"
                $validData = $true
            }
            else {
                Write-Log "Get-DataValid | Data is invalid!"
                $validData = $false
            }
        }
        'gas'{
            Write-Log "Get-DataValid | Date: $($energyData.Date)"
            # Verify if data is up to date
            if((Get-Date) -ge $energyData[0].Date -and (Get-Date) -lt (Get-Date $energyData[0].Date).AddDays(1)) {
                Write-Log "Get-DataValid | Data is valid"
                $validData = $true
            }
            else {
                Write-Log "Get-DataValid | Data is invalid!"
                $validData = $false
            }
        }
    }
    return $validData
}
function Update-Prices {
    param(
        [Parameter(Mandatory=$True,HelpMessage="Eletric or Gas")]
        [ValidateSet("electric", "gas")]
        [string]$energyType,
        [Parameter(Mandatory=$True,HelpMessage="Today or tomorrow")]
        [ValidateSet("Today", "Tomorrow")]
        [string]$day
    )
    
    # Get new values
    switch("$energyType $day") {
        "electric Today" {
            Write-Log "Update-Prices | Get electric prices of today"
            $validData = $false
            # If it is 00 hour and prices of Today are processed, check wether prices of tomorrow fullfill
            if($(Get-Date -Format 'HH') -eq '00') {
                Write-Log "Update-Prices | It is midnight, retrieve prices of 'tomorrow'"
                $data = Get-StoredPrices -energyType $energyType -day 'Tomorrow' -validateData $False
                Write-Log "Update-Prices | Check if prices are up-to-date"
                $validData = Get-DataValid -energyData $data -energyType $energyType -day $day
            }

            # Do not get new values if prices of tomorrow are used
            if($validData) {
                Write-Log "Update-Prices | Data of tomorrow are used for today"
                $rawData = $null
            }
            else {
                # If data is not valid (if checked) then be sure $data is empty
                $data = $null
                Write-Log "Update-Prices | Retrieve new values"
                $rawData = Invoke-RestMethod -Method Get -Uri "https://enever.nl/api/stroomprijs_vandaag.php?token=$($env:EneverAPItoken)"
            }
            
        }
        "electric Tomorrow" {
            Write-Log "Update-Prices | Get electric prices of tomorrow"
            if((Get-Date -Format 'HH') -ge 15) {
                $rawData = Invoke-RestMethod -Method Get -Uri "https://enever.nl/api/stroomprijs_morgen.php?token=$($env:EneverAPItoken)"
            }
            else {
                Write-Log "Update-Prices | No update possible for tomorrow prices, this will be available after 15:00o clock. Current time: $(Get-Date -Format 'HH:mm')"
                $rawData = $null
            }
        }
        "gas Today" {
            Write-Log "Update-Prices | Get gas prices"
            $rawData = Invoke-RestMethod -Method Get -Uri "https://enever.nl/api/gasprijs_vandaag.php?token=$($env:EneverAPItoken)"
        }
        default {$rawData = $null}
    }
    
    Write-Log "Update-Prices | Verify if prices are retrieved"
    if($rawData -and $rawData.status) {
        # Convert string data to Date and Float values
        Write-Log "Update-Prices | Prices retrieved, convert data to PowerShell accepted values"
        $data = Convert-DataArray -DataArray $rawData.data

        # Verify if data is updated
        Write-Log "Update-Prices | Check if prices are up-to-date"
        $validData = Get-DataValid -energyData $data -energyType $energyType -day $day
        if($validData) {
            # Export data
            Write-Log "Update-Prices | Prices are up-to-date, write prices to file"
            $data | Export-Clixml -Path ".\DynamicTariff2MQTT\Data\$($energyType)_$($day).xml" -Force
        }
        else {
            Write-Log "Update-Prices | Data is not up to date, remove stored prices as well and return null"
            if($env:EnableLog) {
                # Export data for debugging
                $data | Export-Clixml -Path ".\DynamicTariff2MQTT\Data\debug_$($energyType)_$($day).xml" -Force
            }
            Remove-Item -Path ".\DynamicTariff2MQTT\Data\$($energyType)_$($day).xml"
            $data = $null
        }
    }
    elseif($data) {
        # Export data
        Write-Log "Update-Prices | Data of tomorrow can be used for today, write to disk"
        $data | Export-Clixml -Path ".\DynamicTariff2MQTT\Data\$($energyType)_$($day).xml" -Force
    }
    else {
        Write-Log "Update-Prices | No prices retrieved, return null"
        $data = $null
    }

    # Publish raw data
    Publish-RawPrices -energyData $data -energyType $energyType -day $day
    return $data
}
function Get-StoredPrices {
    param(
        [Parameter(Mandatory=$True,HelpMessage="Eletric or Gas")]
        [ValidateSet("electric", "gas")]
        [string]$energyType,
        [Parameter(Mandatory=$True,HelpMessage="Today or Tomorrow")]
        [ValidateSet("Today", "Tomorrow")]
        [string]$day,
        [Parameter(Mandatory=$False,HelpMessage="Wether you want to verify data")]
        [bool]$validateData = $true
    )
    Write-Log "Get-StoredPrices | Retrieve $energyType prices $day from disk"
    # Load stored prices
    if(Test-Path -Path ".\DynamicTariff2MQTT\Data\$($energyType)_$($day).xml") {
        Write-Log "Get-StoredPrices | Get stored $energyType prices of $day"
        $data = Import-Clixml ".\DynamicTariff2MQTT\Data\$($energyType)_$($day).xml"

        # Check if data is up-to-date
        if($validateData) {
            Write-Log "Get-StoredPrices | Validate data and check if prices are up-to-date"
            $validData = Get-DataValid -energyData $data -energyType $energyType -day $day
            if($validData) {
                Write-Log "Get-StoredPrices | Data is up-to-date"
            }
            else {
                Write-Log "Get-StoredPrices | Data is out-dated, remove stored prices and retrieve new ones"
                Remove-Item -Path ".\DynamicTariff2MQTT\Data\$($energyType)_$($day).xml"
                $data = Update-Prices -energyType $energyType -day $day
            }
        }
        else {
            Write-Log "Get-StoredPrices | Do not validate data"
        }
    }
    else {
        Write-Log "Get-StoredPrices | No data stored, retrieve new ones"
        $data = Update-Prices -energyType $energyType -day $day
    }
    return $data
}

# Load MQTT module
Add-Type -Path ".\Modules\M2Mqtt.Net.dll"
Write-Log "M2MQtt module loaded"

# Verify if MQTT port is filled
if(!($env:MQTTport)) {
    $env:MQTTport = 1883
    Write-Log "Default MQTT port selected"
}

# Verify if MQTT address is filled
if(!$($env:MQTTserver)) {
    Write-Log "No MQTT server defined! Stop script"
    exit
}
# Test-Netconnection not available
# elseif(!$(Test-NetConnection -ComputerName $env:MQTTserver).PingSucceeded) {
#     Write-Log "MQTT server is unreachable!"
#     exit
# }

# Verify if Enever API token is filled
if(!$($env:EneverAPItoken)) {
    Write-Log "No Enever API token defined! Stop script"
    exit
}

# Define MQTT client object
$MQTTobject = New-Object uPLibrary.Networking.M2Mqtt.MqttClient($env:MQTTserver, $env:MQTTport, $false, [uPLibrary.Networking.M2Mqtt.MqttSslProtocols]::None, $null, $null)

Write-Log "Connecting to MQTT server $env:MQTTserver:$env:MQTTport"
if($env:MQTTuser -or $env:MQTTpassword) {
    # Connect with username and password
    $MQTTobject.Connect([guid]::NewGuid(), $env:MQTTuser, $env:MQTTpassword) 
}
else{
    # Connect anonymous
    $MQTTobject.Connect([guid]::NewGuid()) 
}

switch($(Get-Date -Format 'HH')) {
    "00" {
        Write-Log "It is midnight, update today's prices"
        $dataToday = Update-Prices -energyType 'electric' -day 'Today'
        Remove-Item -Path ".\DynamicTariff2MQTT\Data\electric_tomorrow.xml"
        $dataTomorrow = $null

        # Replace tomorrow data
        Publish-RawPrices -energyData $dataTomorrow -energyType electric -day Tomorrow
    }
}

# Load electric prices tomorrow
$dataToday = Get-StoredPrices -energyType 'electric' -day 'Today'
$dataTomorrow = Get-StoredPrices -energyType 'electric' -day 'Tomorrow'
$dataGas = Get-StoredPrices -energyType 'gas' -day 'Today'

<#
Those actions are not necessary anymore since the data will be checked every hour (if it is not up-to-date, it will retrieve new prices already)
switch($(Get-Date -Format 'HH')) {
    "00" {
        Write-Log "It is midnight, update today's prices"
        $dataToday = Update-Prices -energyType 'electric' -day 'Today'
        Remove-Item -Path ".\DynamicTariff2MQTT\Data\electric_tomorrow.xml"
        $dataTomorrow = $null

        # Replace tomorrow data
        Publish-RawPrices -energyData $dataTomorrow -energyType electric -day Tomorrow
    }
    "06" {
        Write-Log "It is 6 o clock, update gas prices"
        $dataGas = Update-Prices -energyType 'gas' -day 'Today'
    }
    "15" {
        Write-Log "It is 15 o clock, update tomorrow prices"
        $dataTomorrow = Update-Prices -energyType 'electric' -day 'Tomorrow'
    }
}
#>

Write-Log "Publish electric statistics"
[pscustomobject]$totalElectricStatistics = @{}
# Publish electric topics
if($dataToday) {
    Write-Log "Publish message to MQTT server $env:MQTTserver:$env:MQTTport - Todays prices"
    $energySuppliers = $dataToday | Get-Member -MemberType NoteProperty | Where-Object Name -ne 'Date'
    foreach($energySupplier in $energySuppliers.Name) {
        # If the filter is empty, process ALL energy suppliers, if it is set, only process the filtered one and the Exchange
        if(!($env:ElectricSupplierFilter) -or $env:ElectricSupplierFilter -eq $energySupplier -or $energySupplier -eq "Exchange") {
            Write-Log "Collect statistics of $energySupplier electric"
            $electricStatistics = Get-Statistics -energyDataToday $dataToday -energyDataTomorrow $dataTomorrow -energySupplierName $energySupplier -energyType electric
    
            #$statistics | Export-Clixml -Path ".\DynamicTariff2MQTT\Log\statistics.xml"
    
            Write-Log "Publish statistics of $energySupplier today"
            Publish-Statistics -statisticsData $electricStatistics.today -energyType electric -day Today -energySupplierName $energySupplier
            if($dataTomorrow) {
                Write-Log "Publish statistics of $energySupplier tomorrow"
                Publish-Statistics -statisticsData $electricStatistics.tomorrow -energyType electric -day Tomorrow -energySupplierName $energySupplier
            }
            # Add statistiscs to total var
            [PSCustomObject]$entry = @{
                $energySupplier = $electricStatistics
            }
            $totalElectricStatistics += $entry
        }
    }    
}
else{
    Write-Log "Publish Electrc statistics | Error - no data loaded"
}

Write-Log "Publish gas statistics"
[pscustomobject]$totalGasStatistics = @{}
    if($dataGas) {
    $energySuppliers = $dataGas | Get-Member -MemberType NoteProperty | Where-Object Name -ne 'Date'
    foreach($energySupplier in $energySuppliers.Name) {
        # If the filter is empty, process ALL energy suppliers, if it is set, only process the filtered one and the Exchange
        if(!($env:GasSupplierFilter) -or $env:GasSupplierFilter -eq $energySupplier -or $energySupplier -eq "EGSI" -or $energySupplier -eq "EOD") {
            Write-Log "Collect statistics of $energySupplier gas"
            $gasStatistics = Get-Statistics -energyDataToday $dataGas -energySupplierName $energySupplier -energyType gas

            Write-Log "Publish statistics of $energySupplier gas"
            Publish-Statistics -statisticsData $gasStatistics.Today -energyType gas -day Today -energySupplierName $energySupplier

            # Add statistiscs to total var
            [PSCustomObject]$entry = @{
                $energySupplier = $gasStatistics
            }
            $totalGasStatistics += $entry
        }
    }
}
else{
    Write-Log "Publish Gas statistics | Error - no data loaded"
}

Write-Log "Publish total statistics"
# Combine statistics data
[pscustomobject]$totalStatistics = @{
    'electric' = $totalElectricStatistics
    'gas' = $totalGasStatistics
}
$totalStatistics | Export-Clixml -Path ".\DynamicTariff2MQTT\Data\totalStatistics.xml"
Publish-RawStatistics -totalStatisticsData $totalStatistics

# Disconnect MQTT
$MQTTobject.Disconnect()

Write-Log "End of function app"