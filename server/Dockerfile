FROM node:24-alpine AS dashboard
WORKDIR /workspace/server/web
COPY server/web/package*.json ./
RUN npm ci
COPY server/web ./
COPY kindlevel.koplugin/assets/achievements /workspace/kindlevel.koplugin/assets/achievements
COPY kindlevel.koplugin/assets/ui /workspace/kindlevel.koplugin/assets/ui
COPY kindlevel.koplugin/licenses /workspace/kindlevel.koplugin/licenses
RUN npm run check && npm run build

FROM golang:1.26-alpine AS backend
WORKDIR /workspace/server
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /kindlevel-server .

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata && addgroup -g 10001 kindlevel && adduser -D -u 10001 -G kindlevel kindlevel && mkdir /data && chown kindlevel:kindlevel /data
WORKDIR /app
COPY --from=backend /kindlevel-server /app/kindlevel-server
COPY --from=dashboard /workspace/server/web/dist /app/web
COPY LICENSE /app/LICENSE
USER kindlevel
ENV KINDLEVEL_ADDR=:8080 KINDLEVEL_DATA_DIR=/data KINDLEVEL_WEB_DIR=/app/web TZ=UTC
EXPOSE 8080
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["/app/kindlevel-server"]
