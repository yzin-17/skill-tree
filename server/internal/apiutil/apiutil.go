package apiutil

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
)

type Error struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *Error) Error() string                     { return e.Code }
func Fail(status int, code, message string) *Error { return &Error{status, code, message} }
func Write(w http.ResponseWriter, status int, data any) {
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]any{"data": data})
}
func WriteError(w http.ResponseWriter, err error) {
	var api *Error
	if !errors.As(err, &api) {
		api = Fail(500, "internal_error", "服务暂不可用，请重试。")
	}
	w.WriteHeader(api.Status)
	json.NewEncoder(w).Encode(map[string]any{"error": api})
}
func Decode(w http.ResponseWriter, r *http.Request, target any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return Fail(400, "invalid_json", "请求字段或 JSON 格式无效。")
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return Fail(400, "invalid_json", "请求只能包含一个 JSON 对象。")
	}
	return nil
}

var uuidPattern = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

func ValidID(id string) bool { return uuidPattern.MatchString(id) }
func ID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("系统随机数不可用")
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	s := hex.EncodeToString(b[:])
	return s[:8] + "-" + s[8:12] + "-" + s[12:16] + "-" + s[16:20] + "-" + s[20:]
}
func NotFound() *Error { return Fail(404, "not_found", "记录不存在或不可访问。") }
