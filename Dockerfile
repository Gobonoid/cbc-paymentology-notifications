FROM golang:1-alpine AS build

RUN apk update && apk add make git gcc musl-dev protobuf bash

ARG GITHUB_TOKEN
ARG SERVICE

RUN git config --global url."https://${GITHUB_TOKEN}:x-oauth-basic@github.com/".insteadOf "https://github.com/"

WORKDIR /go/src/github.com/utilitywarehouse/${SERVICE}
ADD . /go/src/github.com/utilitywarehouse/${SERVICE}

RUN make clean
RUN make ${SERVICE}

RUN mv ${SERVICE} /${SERVICE}

FROM alpine:latest

ARG SERVICE

ENV APP=${SERVICE}

RUN apk add --no-cache ca-certificates && mkdir /app
COPY --from=build /${SERVICE} /app/${SERVICE}

ENTRYPOINT exec /app/${APP}
