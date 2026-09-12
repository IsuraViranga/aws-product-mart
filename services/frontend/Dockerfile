# ---- Stage 1: Build React app ----
FROM node:22-alpine AS builder

WORKDIR /build
COPY package*.json ./
RUN npm install

COPY public/ ./public/
COPY src/ ./src/

RUN npm run build

# ---- Stage 2: Serve with Nginx ----
FROM nginx:1.29-alpine

# This base image ships curl, which currently carries ten unpatched critical
# CVEs. Nothing in this image uses it: the healthcheck below uses busybox wget
# and nginx's entrypoint scripts use envsubst. Removing it cut criticals from
# 13 to (measured after this change - see the CI scan summary).
RUN apk del curl 2>/dev/null || true

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built React app
COPY --from=builder /build/build /usr/share/nginx/html

# Run as non-root user
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && chown nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:80/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
