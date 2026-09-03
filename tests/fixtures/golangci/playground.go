package fixture

import (
	"fmt"
	"net/http"
	"strings"
)

func beforeSeparator(value string) string {
	if index := strings.Index(value, ":"); index >= 0 {
		return value[:index]
	}
	return value
}

func fetch(url string) error {
	request, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return fmt.Errorf("fetch failed: %v", err)
	}
	if response.StatusCode == 404 {
		return fmt.Errorf("missing: %s", url)
	}
	return nil
}
