# AASX Server Blazor UI Dockerfile (Standalone)
# Builds the standalone Blazor server for AASX viewing
# Modified version of the original AASX Package Explorer

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

# Set working directory
WORKDIR /src

# Copy the entire server source code
COPY . .

# Set working directory to the Blazor project
WORKDIR /src/src

# Restore dependencies
RUN dotnet restore AasxServerBlazor/AasxServerBlazor.csproj

# Build the application
RUN dotnet build AasxServerBlazor/AasxServerBlazor.csproj -c Release -o /app/build

# Publish the application
RUN dotnet publish AasxServerBlazor/AasxServerBlazor.csproj -c Release -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime

# Set working directory
WORKDIR /app

# Copy published application
COPY --from=build /app/publish .

# Create directory for AASX files (will be mounted from host)
RUN mkdir -p /app/data

# Create a script to start Blazor server without pre-loading files
RUN echo '#!/bin/bash\n\
echo "Starting Blazor server for on-demand file serving..."\n\
# Start the Blazor server - it will serve files from data directory\n\
exec dotnet AasxServerBlazor.dll --no-security --data-path ./data --external-blazor http://localhost:5001\n\
' > /app/start.sh && chmod +x /app/start.sh

# Expose port
EXPOSE 5001

# Set environment variables
ENV ASPNETCORE_URLS=http://+:5001
ENV ASPNETCORE_ENVIRONMENT=Production
ENV AASX_DATA_PATH=./data
ENV AASX_SERVER_PORT=5001

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5001/health || exit 1

# Start the application with file copying script
CMD ["/app/start.sh"] 