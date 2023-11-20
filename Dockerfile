# escape=`

# Use the official .NET Core SDK image for building the application
FROM mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2019

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='Continue';"]

RUN  Invoke-WebRequest `
            -UseBasicParsing `
            -Uri https://github.com/cisagov/ScubaGear/releases/download/0.3.0/ScubaGear-0.3.0.zip `
            -OutFile 'c:\\scubagear.zip'; `
        Expand-Archive -LiteralPath "c:\\scubagear.zip" -DestinationPath "c:\\scuba"; `
		Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force; `
		c:\\scuba\ScubaGear-0.3.0\\SetUp.ps1; `
		Import-Module -Name 'c:\\scuba\\ScubaGear-0.3.0\\PowerShell\\ScubaGear';  
		
SHELL ["cmd", "/S", "/C"]

WORKDIR /app

# Copy the .csproj and restore dependencies
COPY *.csproj .
RUN dotnet restore

# Copy the remaining files and build the application
COPY . .
RUN dotnet publish -c Release -o out

# Use the smaller ASP.NET Core runtime image for the final image
#FROM mcr.microsoft.com/dotnet/core/aspnet:3.1
#WORKDIR /app
#COPY --from=build /app/out .

# Expose the port
EXPOSE 8080

# Start the application
ENTRYPOINT ["dotnet", "c:/app/out/scubapwshapi.dll"]
