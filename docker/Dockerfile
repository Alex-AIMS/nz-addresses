FROM postgis/postgis:16-3.4

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Pacific/Auckland

# Install essential tools
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    ca-certificates \
    supervisor \
    unzip \
    gdal-bin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install .NET 8
RUN wget https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y dotnet-sdk-8.0 aspnetcore-runtime-8.0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create appuser
RUN useradd -m -s /bin/bash appuser

# Copy source code
COPY src /home/appuser/src
RUN chown -R appuser:appuser /home/appuser/src

# Build and publish the WebApi
USER appuser
WORKDIR /home/appuser/src
RUN dotnet restore NzAddresses.sln \
    && dotnet publish NzAddresses.WebApi/NzAddresses.WebApi.csproj -c Release -o /home/appuser/publish

# Switch back to root for system setup
USER root

# Copy ETL scripts
COPY scripts /home/appuser/scripts
RUN chown -R appuser:appuser /home/appuser/scripts \
    && chmod +x /home/appuser/scripts/*.sh

# Copy database initialization scripts
COPY docker/initdb /docker-entrypoint-initdb.d/
RUN chmod -R 755 /docker-entrypoint-initdb.d/

# Copy supervisord configuration
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Set PostgreSQL environment (will be overridden by config.env at runtime)
ENV POSTGRES_USER=nzuser
ENV POSTGRES_PASSWORD=nzpass
ENV POSTGRES_DB=nz_addresses_db
ENV PGDATA=/var/lib/postgresql/data

# Initialize database on first run (PostGIS image handles this automatically)
# The SQL files in /docker-entrypoint-initdb.d/ will be executed automatically

# Expose ports
EXPOSE 5432 8080

# Set environment for API
ENV ASPNETCORE_URLS=http://0.0.0.0:8080
ENV ASPNETCORE_ENVIRONMENT=Production

# Create startup script that runs both PostgreSQL and the API
RUN echo '#!/bin/bash\n\
set -e\n\
# Start PostgreSQL in background\n\
docker-entrypoint.sh postgres &\n\
# Wait for PostgreSQL to be ready\n\
until pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}; do\n\
  echo "Waiting for PostgreSQL..."\n\
  sleep 2\n\
done\n\
echo "PostgreSQL is ready"\n\
# Start the .NET API\n\
su appuser -c "dotnet /home/appuser/publish/NzAddresses.WebApi.dll"\n\
' > /start.sh && chmod +x /start.sh

CMD ["/start.sh"]
