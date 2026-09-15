/*
 * 最小可用的 Extension API Server（聚合层实战）
 *
 * 这个程序演示 K8s 聚合层（Aggregation Layer）的核心：
 *   1. 自己实现一个独立的 API Server，注册一个新的 API Group
 *   2. 通过 APIService 对象告诉主 API Server："hello.example.com 的请求转发给我"
 *   3. 客户端用原生 kubectl 访问它，感觉不到它其实是个独立进程
 *
 * 对外暴露的 API：
 *   GET    /apis/hello.example.com/v1/namespaces/{ns}/hellos          列出
 *   GET    /apis/hello.example.com/v1/namespaces/{ns}/hellos/{name}   读取
 *   POST   /apis/hello.example.com/v1/namespaces/{ns}/hellos          创建
 *   DELETE /apis/hello.example.com/v1/namespaces/{ns}/hellos/{name}   删除
 *   GET    /apis/hello.example.com/v1                                 发现（discovery）
 *
 * 教学要点：
 *   - 聚合层 = API Server 的"反向代理 + 二次分发"
 *   - extension-apiserver 必须自己实现认证/授权委托（authn/authz delegation）
 *     否则任何人都能绕过 RBAC 直接访问它（这是最容易踩的坑）
 *   - 数据存在内存里，重启即丢（生产要落 etcd）
 */
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	group   = "hello.example.com"
	version = "v1"
)

// Hello 是我们自定义的资源类型。
// 注意：这里用普通 Go struct 而不是 k8s 的 TypeMeta/ObjectMeta，
// 是为了让代码能一眼看懂；真正的 operator 项目应该用 k8s.io/apimachinery 的类型。
type Hello struct {
	Kind       string            `json:"kind"`
	APIVersion string            `json:"apiVersion"`
	Metadata   ObjectMeta        `json:"metadata"`
	Spec       HelloSpec         `json:"spec"`
	Status     HelloStatus       `json:"status,omitempty"`
}

type ObjectMeta struct {
	Name              string            `json:"name"`
	Namespace         string            `json:"namespace,omitempty"`
	UID               string            `json:"uid,omitempty"`
	ResourceVersion   string            `json:"resourceVersion,omitempty"`
	CreationTimestamp string            `json:"creationTimestamp,omitempty"`
	Labels            map[string]string `json:"labels,omitempty"`
}

type HelloSpec struct {
	Message string `json:"message"`
	Replicas int   `json:"replicas,omitempty"`
}

type HelloStatus struct {
	Phase   string `json:"phase,omitempty"`
	ReadyAt string `json:"readyAt,omitempty"`
}

type HelloList struct {
	Kind       string  `json:"kind"`
	APIVersion string  `json:"apiVersion"`
	Metadata   struct{} `json:"metadata"`
	Items      []Hello `json:"items"`
}

// ---------- 内存存储 ----------
var (
	mu     sync.RWMutex
	store  = map[string]map[string]Hello{} // namespace -> name -> Hello
	counter int
)

func put(ns string, h Hello) {
	mu.Lock()
	defer mu.Unlock()
	if store[ns] == nil {
		store[ns] = map[string]Hello{}
	}
	store[ns][h.Metadata.Name] = h
}

func get(ns, name string) (Hello, bool) {
	mu.RLock()
	defer mu.RUnlock()
	h, ok := store[ns][name]
	return h, ok
}

func list(ns string) []Hello {
	mu.RLock()
	defer mu.RUnlock()
	out := []Hello{}
	for _, h := range store[ns] {
		out = append(out, h)
	}
	return out
}

func del(ns, name string) bool {
	mu.Lock()
	defer mu.Unlock()
	if _, ok := store[ns][name]; !ok {
		return false
	}
	delete(store[ns], name)
	return true
}

func nextRV() string {
	counter++
	return fmt.Sprintf("%d", counter)
}

// ---------- HTTP 处理 ----------
func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]interface{}{
		"kind":       "Status",
		"apiVersion": "v1",
		"status":     "Failure",
		"message":    msg,
		"code":       code,
	})
}

// delegatingAuthz 演示【认证/授权委托】—— 聚合层最重要的机制，也最容易踩坑。
//
// 教学要点 1：主 API Server 转发请求时，走的是「双通道」：
//   - 客户端身份：通过 X-Remote-User / X-Remote-Group 请求头传递
//   - 自身身份：用客户端证书（CN=aggregator 或 system:kube-aggregator）建 TLS
//   所以这里既要认 Bearer token，也要认主 API Server 的客户端证书。
//   本实验第一版只认 Bearer token，导致 kubectl 全部 401 —— 真实踩坑。
//
// 教学要点 2：discovery (/apis/<group>/<version>) 必须公开，
//   主 API Server 探测它时既不带 token 也不带证书。
func delegatingAuthz(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 通道 A：主 API Server 转发来的（带 peer cert 或 X-Remote-User）
		remoteUser := r.Header.Get("X-Remote-User")
		peerCN := ""
		if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
			peerCN = r.TLS.PeerCertificates[0].Subject.CommonName
		}
		if remoteUser != "" || strings.HasPrefix(peerCN, "system:") || peerCN == "aggregator" {
			log.Printf("[authz] 接受（主 API Server 转发）remote-user=%q peer-cn=%q path=%s",
				remoteUser, peerCN, r.URL.Path)
			next(w, r)
			return
		}

		// 通道 B：直连客户端带 Bearer token（真实实现应发 TokenReview 校验）
		if authz := r.Header.Get("Authorization"); strings.HasPrefix(authz, "Bearer ") {
			log.Printf("[authz] 接受（Bearer token 前8位=%s...）path=%s", authz[7:15], r.URL.Path)
			next(w, r)
			return
		}

		log.Printf("[authz] 拒绝：既无主 API Server 身份也无 Bearer token (peer-cn=%q)", peerCN)
		writeErr(w, http.StatusUnauthorized, "Unauthorized: missing bearer token (delegated authn required)")
	}
}

// handleDiscovery 返回 API 发现文档 —— kubectl 靠它知道有哪些 resource/verb
func handleDiscovery(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, map[string]interface{}{
		"kind":       "APIResourceList",
		"apiVersion": "v1",
		"groupVersion": group + "/" + version,
		"resources": []map[string]interface{}{
			{
				"name":         "hellos",
				"singularName": "hello",
				"namespaced":   true,
				"kind":         "Hello",
				"verbs":        []string{"get", "list", "create", "delete", "watch"},
				"shortNames":   []string{"hi"},
			},
		},
	})
}

// handleHello 处理 /apis/hello.example.com/v1/namespaces/{ns}/hellos[/{name}]
func handleHello(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	// 期望: apis / hello.example.com / v1 / namespaces / {ns} / hellos [/ {name}]
	var ns, name string
	for i, p := range parts {
		if p == "namespaces" && i+1 < len(parts) {
			ns = parts[i+1]
		}
		if p == "hellos" && i+1 < len(parts) {
			name = parts[i+1]
		}
	}

	log.Printf("[api] %s ns=%q name=%q", r.Method, ns, name)

	switch r.Method {
	case http.MethodGet:
		if name != "" {
			h, ok := get(ns, name)
			if !ok {
				writeErr(w, 404, fmt.Sprintf("hellos.hello.example.com %q not found", name))
				return
			}
			writeJSON(w, 200, h)
			return
		}
		writeJSON(w, 200, HelloList{
			Kind:       "HelloList",
			APIVersion: group + "/" + version,
			Items:      list(ns),
		})

	case http.MethodPost:
		var h Hello
		if err := json.NewDecoder(r.Body).Decode(&h); err != nil {
			writeErr(w, 400, "bad request: "+err.Error())
			return
		}
		h.Kind = "Hello"
		h.APIVersion = group + "/" + version
		h.Metadata.Namespace = ns
		h.Metadata.UID = fmt.Sprintf("%d", time.Now().UnixNano())
		h.Metadata.ResourceVersion = nextRV()
		h.Metadata.CreationTimestamp = time.Now().UTC().Format(time.RFC3339)
		// 模拟 controller：收到请求后填充 status
		h.Status = HelloStatus{
			Phase:   "Ready",
			ReadyAt: time.Now().UTC().Format(time.RFC3339),
		}
		put(ns, h)
		writeJSON(w, 201, h)

	case http.MethodDelete:
		if !del(ns, name) {
			writeErr(w, 404, fmt.Sprintf("hellos.hello.example.com %q not found", name))
			return
		}
		writeJSON(w, 200, map[string]interface{}{
			"kind": "Status", "apiVersion": "v1", "status": "Success",
		})

	default:
		writeErr(w, 405, "method not allowed")
	}
}

func handleHealthz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(200)
	w.Write([]byte("ok"))
}

func handleOpenAPI(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, map[string]interface{}{
		"swagger": "2.0",
		"info":    map[string]string{"title": "Hello Aggregated API", "version": version},
		"paths":   map[string]interface{}{},
	})
}

func main() {
	certFile := os.Getenv("TLS_CERT")
	keyFile := os.Getenv("TLS_KEY")
	if certFile == "" {
		certFile = "/etc/apiserver/certs/tls.crt"
	}
	if keyFile == "" {
		keyFile = "/etc/apiserver/certs/tls.key"
	}

	mux := http.NewServeMux()
	// discovery / openapi / healthz 必须公开：主 API Server 探测它们时不带凭据
	mux.HandleFunc("/apis/"+group+"/"+version, handleDiscovery)
	mux.HandleFunc("/openapi/v2", handleOpenAPI)
	mux.HandleFunc("/healthz", handleHealthz)
	// 资源端点走认证委托
	mux.HandleFunc("/apis/"+group+"/"+version+"/", delegatingAuthz(handleHello))

	addr := ":8443"
	log.Printf("[boot] extension-apiserver 启动 group=%s version=%s addr=%s", group, version, addr)
	log.Printf("[boot] 教学提示：本服务必须通过 APIService 注册才能被 kubectl 访问")
	if err := http.ListenAndServeTLS(addr, certFile, keyFile, mux); err != nil {
		log.Fatalf("[fatal] %v", err)
	}
}
