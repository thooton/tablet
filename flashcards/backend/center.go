package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"tablet/appload"
	"time"
)

// The command center: its flashcards sync, and pairing, which gives the
// tablet a token of its own for the flashcards (and nothing else) when the
// code it shows is typed on the website's Tablet page.

// defaultServer is the user's command center. Its address is no secret
// (the website is served there); the token is, and the tablet never sees
// the delta token, only the one its pairing makes.
const defaultServer = "https://edit.mimilearn.org/api/delta"

var errUnpaired = errors.New("the command center no longer knows this tablet")

type login struct {
	Server string `json:"server"`
	Token  string `json:"token"`
}

type center struct {
	path   string // login.json
	client *http.Client
}

func newCenter(dir string) *center {
	return &center{path: filepath.Join(dir, "login.json"), client: &http.Client{Timeout: 2 * time.Minute}}
}

func (c *center) login() login {
	var l login
	if data, err := os.ReadFile(c.path); err == nil {
		json.Unmarshal(data, &l)
	}
	if l.Server == "" {
		l.Server = appload.Env("FLASHCARDS_SERVER", defaultServer)
	}
	return l
}

func (c *center) save(l login) error {
	data, _ := json.Marshal(l)
	tmp := c.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, c.path)
}

func (c *center) forget() {
	l := c.login()
	l.Token = ""
	c.save(l)
}

// sync posts what changed here and answers the command center's reply.
func (c *center) sync(body []byte) ([]byte, error) {
	l := c.login()
	if l.Token == "" {
		return nil, errUnpaired
	}
	req, err := http.NewRequest("POST", l.Server+"/flashcards/sync", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+l.Token)
	req.Header.Set("Content-Type", "application/json")
	return c.do(req)
}

type pairing struct {
	Code    string    `json:"code"`
	Secret  string    `json:"secret"`
	Expires time.Time `json:"expires"`
}

func (c *center) startPairing() (pairing, error) {
	var p pairing
	req, err := http.NewRequest("POST", c.login().Server+"/flashcards/pair", strings.NewReader(`{"name":"reMarkable"}`))
	if err != nil {
		return p, err
	}
	data, err := c.do(req)
	if err != nil {
		return p, err
	}
	err = json.Unmarshal(data, &p)
	return p, err
}

// pollPairing answers the token once the code has been approved, "" while
// it waits, and an error when the pairing is gone.
func (c *center) pollPairing(p pairing) (string, error) {
	req, err := http.NewRequest("GET", c.login().Server+"/flashcards/pair/"+p.Secret, nil)
	if err != nil {
		return "", err
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return "", errors.New("No connection.")
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	switch resp.StatusCode {
	case http.StatusAccepted:
		return "", nil
	case http.StatusOK:
		var got struct{ Token string }
		if json.Unmarshal(data, &got) != nil || got.Token == "" {
			return "", errors.New("The command center's answer was unreadable.")
		}
		return got.Token, nil
	case http.StatusNotFound:
		return "", errors.New("The code expired.")
	}
	return "", fmt.Errorf("The command center answered %d.", resp.StatusCode)
}

func (c *center) do(req *http.Request) ([]byte, error) {
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, errors.New("No connection.")
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	if err != nil {
		return nil, errors.New("No connection.")
	}
	switch {
	case resp.StatusCode == http.StatusUnauthorized:
		return nil, errUnpaired
	case resp.StatusCode == http.StatusNotFound || resp.StatusCode == http.StatusMethodNotAllowed:
		return nil, errors.New("The command center needs updating.")
	case resp.StatusCode >= 300:
		var e struct{ Error string }
		if json.Unmarshal(data, &e) == nil && e.Error != "" {
			msg := strings.ToUpper(e.Error[:1]) + e.Error[1:]
			return nil, errors.New(strings.TrimSuffix(msg, ".") + ".")
		}
		return nil, fmt.Errorf("The command center answered %d.", resp.StatusCode)
	}
	return data, nil
}
