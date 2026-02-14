FROM mcr.microsoft.com/dotnet/aspnet:8.0.24 AS base
WORKDIR /app
EXPOSE 5003

FROM mcr.microsoft.com/dotnet/sdk:8.0.418 AS build
WORKDIR /src

# Copy project files for restore
COPY ["src/NzAddresses.WebApi/NzAddresses.WebApi.csproj", "src/NzAddresses.WebApi/"]
COPY ["src/NzAddresses.Core/NzAddresses.Core.csproj", "src/NzAddresses.Core/"]
COPY ["src/NzAddresses.Data/NzAddresses.Data.csproj", "src/NzAddresses.Data/"]
COPY ["src/NzAddresses.Domain/NzAddresses.Domain.csproj", "src/NzAddresses.Domain/"]

# Restore dependencies
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
RUN dotnet restore "src/NzAddresses.WebApi/NzAddresses.WebApi.csproj"

# Copy source code
COPY src/ src/

# Build
WORKDIR "/src/src/NzAddresses.WebApi"
RUN dotnet build "NzAddresses.WebApi.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "NzAddresses.WebApi.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app

# Install curl for health checks
USER root
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY --from=publish /app/publish .

# Run as non-root user
USER app

ENV ASPNETCORE_URLS=http://+:5003
ENTRYPOINT ["dotnet", "NzAddresses.WebApi.dll"]
