# Use the official n8n image as the builder
FROM n8nio/n8n:latest AS builder

# --- Final Stage for the N8n Application ---
FROM node:lts-alpine

# Set the working directory where the app will run
WORKDIR /usr/local/bin/n8n

# Create a non-root user for better security
RUN addgroup --system n8n && adduser --system --ingroup n8n n8n

# Copy n8n binaries and dependencies from the builder stage
COPY --from=builder /usr/local/bin/n8n /usr/local/bin/n8n
COPY --from=builder /usr/local/lib/node_modules/n8n /usr/local/lib/node_modules/n8n

# Fix ownership so the non-root user can access the files
RUN chown -R n8n:n8n /usr/local/bin/n8n /usr/local/lib/node_modules/n8n

# Switch to non-root user
USER n8n

# Expose default n8n port
EXPOSE 5678

# Start the n8n process
CMD ["n8n"]
