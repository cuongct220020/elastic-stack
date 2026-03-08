# Use a stable and lightweight Python base image
FROM python:3.12-slim

# ===== ENVIRONMENT VARIABLES =====
# Prevent Python from writing .pyc files to disk
ENV PYTHONDONTWRITEBYTECODE=1
# Ensure stdout/stderr are unbuffered so logs flow directly to the container log stream (crucial for Elastic Agent)
ENV PYTHONUNBUFFERED=1

# ===== SECURITY: Create Non-Root User =====
# Running as root inside a container is a security risk. 
RUN addgroup --system appgroup && adduser --system --group appuser

# Set the working directory
WORKDIR /app

# ===== CACHE OPTIMIZATION: Install dependencies first =====
# Copy only requirements.txt first to leverage Docker's build cache
COPY requirements.txt .

# Upgrade pip and install dependencies without storing cache
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ===== COPY APPLICATION CODE =====
COPY . .

# Change ownership of the application directory to the non-root user
RUN chown -R appuser:appgroup /app

# Create log directory and grant ownership to the non-root user
RUN mkdir -p /var/log/demo-app && chown -R appuser:appgroup /var/log/demo-app

# Switch to the non-root user
USER appuser

# Expose the application port
EXPOSE 1337

# Start the FastAPI application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "1337"]
