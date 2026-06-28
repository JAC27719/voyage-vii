# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:10.0.203-noble AS build
WORKDIR /src

COPY Directory.Build.props Directory.Packages.props Hydra.slnx global.json ./
COPY src/Hydra.Api/Hydra.Api.csproj src/Hydra.Api/
COPY src/Hydra.Seeder/Hydra.Seeder.csproj src/Hydra.Seeder/
COPY tests/Hydra.Api.Tests/Hydra.Api.Tests.csproj tests/Hydra.Api.Tests/
RUN dotnet restore Hydra.slnx

COPY . .
RUN dotnet publish src/Hydra.Api/Hydra.Api.csproj \
    --configuration Release \
    --no-restore \
    --output /app/api
RUN dotnet publish src/Hydra.Seeder/Hydra.Seeder.csproj \
    --configuration Release \
    --no-restore \
    --output /app/seeder

FROM mcr.microsoft.com/dotnet/aspnet:10.0.9-noble AS api
WORKDIR /app
RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/api .
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "Hydra.Api.dll"]

FROM mcr.microsoft.com/dotnet/runtime:10.0.9-noble AS seeder
WORKDIR /app
COPY --from=build /app/seeder .
USER $APP_UID
ENTRYPOINT ["dotnet", "Hydra.Seeder.dll"]
