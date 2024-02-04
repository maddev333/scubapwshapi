# escape=`

# Use the official .NET Core SDK image for building the application
FROM mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2019

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='Continue';"]

RUN  Invoke-WebRequest `
            -UseBasicParsing `
            -Uri https://github.com/cisagov/ScubaGear/releases/download/v1.0.0/ScubaGear-1.0.0.zip `
            -OutFile 'c:\\scubagear.zip'; `
        Expand-Archive -LiteralPath "c:\\scubagear.zip" -DestinationPath "c:\\scuba"; `
		Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force; `
    	c:\\scuba\ScubaGear-1.0.0\\SetUp.ps1; `
    	Import-Module -Name C:\\scuba\\ScubaGear-1.0.0\\PowerShell\\ScubaGear;  
        #$cert = New-SelfSignedCertificate -Subject "CN=scuba" -CertStoreLocation "Cert:\CurrentUser\My" -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256; `
		#Export-Certificate -Cert $cert -FilePath "C:\scuba.cer";

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
ENTRYPOINT ["powershell", "c:/app/runScuba.ps1"]

