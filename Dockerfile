FROM alpine/git:latest AS source

ARG FILEBROWSER_VERSION=v1.5.2-stable

RUN git clone --depth 1 --branch "${FILEBROWSER_VERSION}" \
    https://github.com/gtsteffaniak/filebrowser.git /src

COPY patches/ai-share-link.patch /tmp/ai-share-link.patch
RUN cd /src \
    && git apply --check /tmp/ai-share-link.patch \
    && git apply /tmp/ai-share-link.patch

FROM gtstef/ffmpeg:8.1.2-decode AS ffmpeg

FROM golang:alpine AS backend-build

ARG VERSION=1.5.2-mariko
ARG REVISION=custom-ai-share-link

WORKDIR /app
COPY --from=source /src/backend/ ./
RUN apk update && apk add --no-cache gcc musl-dev
ENV CGO_ENABLED=1
RUN go build -tags mupdf,musl -ldflags="-w -s \
    -X 'github.com/gtsteffaniak/filebrowser/backend/common/version.Version=${VERSION}' \
    -X 'github.com/gtsteffaniak/filebrowser/backend/common/version.CommitSHA=${REVISION}'" \
    -o filebrowser .

FROM node:jod-slim AS frontend-build

WORKDIR /app
COPY --from=source /src/frontend/package.json ./
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && git config --global url."https://github.com/".insteadOf "git@github.com:" \
    && git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
RUN npm install --maxsockets 1
COPY --from=source /src/frontend/ ./
RUN npm run build:docker

FROM alpine:latest

COPY --from=ffmpeg ["/ffmpeg", "/ffprobe", "/usr/local/bin/"]

ENV FILEBROWSER_FFMPEG_PATH=/usr/local/bin/
ENV FILEBROWSER_DATABASE=/home/filebrowser/data/database.db
ENV FILEBROWSER_CONFIG=/home/filebrowser/data/config.yaml
ENV PATH="$PATH:/home/filebrowser"

RUN apk --no-cache add ca-certificates mailcap tzdata curl exiftool \
    && adduser -D -s /bin/true -u 1000 filebrowser

USER filebrowser
WORKDIR /home/filebrowser

COPY --from=backend-build --chown=filebrowser:1000 ["/app/filebrowser", "./"]
COPY --from=backend-build --chown=filebrowser:1000 ["/app/config.yaml", "./data/config.yaml"]
COPY --from=backend-build --chown=filebrowser:1000 ["/app/config.yaml", "./"]
COPY --from=backend-build --chown=filebrowser:1000 ["/app/reduce-rounded-corners.css", "./"]
COPY --from=frontend-build --chown=filebrowser:1000 ["/app/dist/", "./http/dist/"]

RUN ["filebrowser", "version"]
RUN ["ffmpeg", "-version"]
RUN ["ffprobe", "-version"]
RUN ["exiftool", "-ver"]

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl --fail http://localhost:80/health || exit 1

ENTRYPOINT ["./filebrowser"]
