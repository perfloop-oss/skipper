package proxy

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/zalando/skipper/eskip"
	"github.com/zalando/skipper/filters"
	"github.com/zalando/skipper/filters/builtin"
	"github.com/zalando/skipper/filters/fadein"
	"github.com/zalando/skipper/loadbalancer"
	"github.com/zalando/skipper/logging/loggingtest"
	"github.com/zalando/skipper/routing"
	"github.com/zalando/skipper/routing/testdataclient"
)

func newFadeInProofProxy(b *testing.B, algorithmName string, endpointCount int) *Proxy {
	b.Helper()
	const duration = time.Hour
	backends := make([]*httptest.Server, endpointCount)
	route := &eskip.Route{
		Id:          "fadeInProof",
		BackendType: eskip.LBBackend,
		LBAlgorithm: algorithmName,
		Filters: []*eskip.Filter{{
			Name: filters.FadeInName,
			Args: []any{duration},
		}},
	}
	for i := range endpointCount {
		backends[i] = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusNoContent)
		}))
		route.LBEndpoints = append(route.LBEndpoints, &eskip.LBEndpoint{Address: backends[i].URL})
	}

	logger := loggingtest.New()
	registry := routing.NewEndpointRegistry(routing.RegistryOptions{})
	dataClient := testdataclient.New([]*eskip.Route{route})
	rt := routing.New(routing.Options{
		SignalFirstLoad: true,
		FilterRegistry:  builtin.MakeRegistry(),
		DataClients:     []routing.DataClient{dataClient},
		PostProcessors: []routing.PostProcessor{
			loadbalancer.NewAlgorithmProvider(),
			registry,
			fadein.NewPostProcessor(fadein.PostProcessorOptions{EndpointRegistry: registry}),
		},
		Log: logger,
	})
	<-rt.FirstLoad()
	p := WithParams(Params{Routing: rt, EndpointRegistry: registry, AccessLogDisabled: true})

	loaded, _ := rt.Route(httptest.NewRequest(http.MethodGet, "http://example.test/", nil))
	if loaded == nil || len(loaded.LBEndpoints) != endpointCount || loaded.LBFadeInDuration != duration {
		b.Fatal("unexpected route or fade-in setup")
	}
	detected := time.Now().Add(-2 * duration)
	seen := make(map[string]bool, endpointCount)
	for i := range loaded.LBEndpoints {
		ep := &loaded.LBEndpoints[i]
		if seen[ep.Host] {
			b.Fatal("backend endpoints are not distinct")
		}
		seen[ep.Host] = true
		ep.Metrics.SetDetected(detected)
	}

	b.Cleanup(func() {
		p.Close()
		if tr, ok := p.roundTripper.(*http.Transport); ok {
			tr.CloseIdleConnections()
		}
		rt.Close()
		dataClient.Close()
		for _, backend := range backends {
			backend.Close()
		}
		logger.Close()
	})
	return p
}

func BenchmarkFadeInProofServeHTTP(b *testing.B) {
	for _, algorithm := range []loadbalancer.Algorithm{
		loadbalancer.PowerOfRandomNChoices,
		loadbalancer.Random,
		loadbalancer.RoundRobin,
		loadbalancer.ConsistentHash,
	} {
		for _, endpoints := range []int{1, 8, 32, 200} {
			b.Run(fmt.Sprintf("%s/endpoints=%d", algorithm.String(), endpoints), func(b *testing.B) {
				p := newFadeInProofProxy(b, algorithm.String(), endpoints)
				for i := range endpoints * 10 {
					response := httptest.NewRecorder()
					request := httptest.NewRequest(http.MethodGet, "http://example.test/", nil)
					request.RemoteAddr = fmt.Sprintf("192.0.2.%d:12345", i%254+1)
					p.ServeHTTP(response, request)
					if response.Code != http.StatusNoContent {
						b.Fatalf("warmup returned %d, want 204", response.Code)
					}
				}
				b.ResetTimer()
				for i := range b.N {
					response := httptest.NewRecorder()
					request := httptest.NewRequest(http.MethodGet, "http://example.test/", nil)
					request.RemoteAddr = fmt.Sprintf("192.0.2.%d:12345", i%254+1)
					p.ServeHTTP(response, request)
					if response.Code != http.StatusNoContent {
						b.Fatalf("request returned %d, want 204", response.Code)
					}
				}
			})
		}
	}
}
