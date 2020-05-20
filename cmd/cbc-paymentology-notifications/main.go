package main

import (
	"fmt"
	"github.com/kelseyhightower/envconfig"
	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"github.com/utilitywarehouse/cbc-paymentology-notifications/internal/handler"
	"github.com/utilitywarehouse/cbc-paymentology-notifications/internal/router"
	"github.com/utilitywarehouse/cbc/pkg/logger"
	"github.com/utilitywarehouse/go-operational/op"
	"net/http"
	"os"
	"os/signal"
	"syscall"
)

var (
	gitHash = "" // Populated at compile time
)

const (
	appName = "cbc-paymentology-notifications"
	appDesc = "GRPC api to handle integration between CBC and Paymentology"
)

type options struct {
	LogLevel       string `default:"info" split_words:"true" description:"Log level [debug|info|warn|error]"`
	ManagementPort int    `default:"10000" split_words:"true" description:"Port to listen on for HTTP connections to management endpoints"`
	HTTPPort       int    `default:"8080" envconfig:"HTTP_PORT" description:"Port to listen on for incoming http req"`
}

func main() {
	opts := options{}
	err := envconfig.Process("", &opts)
	if err != nil {
		panic("failed to parse ENV config: " + err.Error())
	}
	logger.ConfigureGlobalLogger(&opts.LogLevel)
	go func() {
		if err = serveManagement(opts.ManagementPort); err != nil {
			log.WithError(err).Panic("failed to run ops server")
		}
	}()
	r := router.NewRouter(handler.HTTP{})
	if err := r.Start(fmt.Sprintf(":%d", opts.HTTPPort)); err != nil {
		log.WithError(err).Panic("failed to start http server")
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
}

func serveManagement(port int) error {
	if err := http.ListenAndServe(fmt.Sprintf(":%d", port), op.NewHandler(
		op.NewStatus(appName, appDesc).
			AddOwner("cbc-dev", "#cbcv3").
			AddLink("vcs", fmt.Sprintf("https://github.com/utilitywarehouse/%s", appName)).
			SetRevision(gitHash).ReadyNever(),
	)); err != nil {
		return errors.Wrap(err, "failed to listen and serve")
	}

	return nil
}
