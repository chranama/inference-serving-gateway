FROM golang:1.26-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/gateway ./cmd/gateway

FROM alpine:3.22

RUN adduser -D -g '' gateway

COPY --from=build /out/gateway /usr/local/bin/gateway

USER gateway
EXPOSE 8080

ENTRYPOINT ["gateway"]

