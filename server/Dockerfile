FROM golang:1.27.3-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /skillatlas ./cmd/api

FROM scratch
COPY --from=build /skillatlas /skillatlas
USER 65532:65532
EXPOSE 8447
ENTRYPOINT ["/skillatlas"]
