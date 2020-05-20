package router

import (
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"github.com/utilitywarehouse/cbc-paymentology-notifications/internal/handler"
)

const (
	notificationsURL = "/notifications"
)

//NewRouter creates echo router
func NewRouter(h handler.HTTP) *echo.Echo {
	e := echo.New()
	e.Use(middleware.LoggerWithConfig(middleware.DefaultLoggerConfig))

	e.POST(notificationsURL, h.NewNotification)

	return e
}
