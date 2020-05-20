package handler

import (
	"github.com/davecgh/go-spew/spew"
	"github.com/labstack/echo/v4"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
	"io/ioutil"
	"net/http"
)

//HTTP implements endpoints handling functions
type HTTP struct{}

//NewNotification received
func (h HTTP) NewNotification(c echo.Context) error {
	p, err := ioutil.ReadAll(c.Request().Body)
	if err != nil {
		logrus.Warn("failed to read body")
		spew.Dump(c.Request().Body)
	}
	spew.Dump(string(p))

	if err := c.JSONBlob(http.StatusOK, []byte(`{}`)); err != nil {
		return errors.Wrap(err, "failed to return status OK")
	}
	return nil
}
