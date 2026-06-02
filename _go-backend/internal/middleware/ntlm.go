package middleware

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"strings"
	"unicode/utf16"
)

// NTLM message types
const (
	ntlmNegotiate    = 1
	ntlmChallenge    = 2
	ntlmAuthenticate = 3
)

var ntlmSignature = []byte("NTLMSSP\x00")

type ntlmField struct {
	Len    uint16
	MaxLen uint16
	Offset uint32
}

// ParseNTLMAuthenticate extracts username from a Base64-encoded NTLM Type 3 message.
// Returns empty string if parsing fails.
func ParseNTLMAuthenticate(base64Data string) string {
	data, err := base64.StdEncoding.DecodeString(base64Data)
	if err != nil {
		return ""
	}
	if len(data) < 64 || string(data[:8]) != string(ntlmSignature) {
		return ""
	}
	msgType := binary.LittleEndian.Uint32(data[8:12])
	if msgType != ntlmAuthenticate {
		return ""
	}
	// username field at offset 36 (domain=28, user=36, host=44 after lmResp=12, ntlmResp=20)
	userLen := binary.LittleEndian.Uint16(data[36:38])
	// userMaxLen := binary.LittleEndian.Uint16(data[38:40])
	userOff := binary.LittleEndian.Uint32(data[40:44])

	if int(userOff)+int(userLen) > len(data) {
		return ""
	}
	raw := data[userOff : userOff+uint32(userLen)]
	return strings.TrimRight(string(utf16Decode(raw)), "\x00")
}

func utf16Decode(b []byte) string {
	if len(b)%2 != 0 {
		return ""
	}
	u := make([]uint16, len(b)/2)
	for i := range u {
		u[i] = binary.LittleEndian.Uint16(b[i*2 : i*2+2])
	}
	return string(utf16.Decode(u))
}

func utf16Encode(s string) []byte {
	runes := utf16.Encode([]rune(s))
	b := make([]byte, len(runes)*2)
	for i, r := range runes {
		binary.LittleEndian.PutUint16(b[i*2:], r)
	}
	return b
}

// NTLMChallenge generates a Base64-encoded NTLM Type 2 (Challenge) message.
func NTLMChallenge() string {
	buf := make([]byte, 56) // minimal challenge message

	copy(buf[0:8], ntlmSignature)
	binary.LittleEndian.PutUint32(buf[8:12], ntlmChallenge)

	// TargetName field: empty (len=0, offset points to end of header)
	binary.LittleEndian.PutUint16(buf[12:14], 0)  // len
	binary.LittleEndian.PutUint16(buf[14:16], 0)  // maxlen
	binary.LittleEndian.PutUint32(buf[16:20], 56) // offset (right after fixed header)

	// Flags: NTLMSSP_NEGOTIATE_UNICODE | NTLMSSP_NEGOTIATE_NTLM | NTLMSSP_REQUEST_TARGET | NTLMSSP_NEGOTIATE_ALWAYS_SIGN | NTLMSSP_TARGET_TYPE_SERVER
	flags := uint32(0x00000001 | 0x00000200 | 0x00000004 | 0x00008000 | 0x00010000)
	binary.LittleEndian.PutUint32(buf[20:24], flags)

	// Challenge: 8 random bytes
	nonce := make([]byte, 8)
	rand.Read(nonce)
	copy(buf[24:32], nonce)

	// Context: 8 zero bytes
	// bytes 32-40 already zero

	// TargetInfo field: empty
	binary.LittleEndian.PutUint16(buf[40:42], 0)  // len
	binary.LittleEndian.PutUint16(buf[42:44], 0)  // maxlen
	binary.LittleEndian.PutUint32(buf[44:48], 56) // offset

	// OS Version (optional, 8 bytes): Windows 10.0
	binary.LittleEndian.PutUint16(buf[48:50], 10)    // major
	binary.LittleEndian.PutUint16(buf[50:52], 0)     // minor
	binary.LittleEndian.PutUint16(buf[52:54], 18363) // build (0 == unused)
	binary.LittleEndian.PutUint16(buf[54:56], 0)     // reserved

	return base64.StdEncoding.EncodeToString(buf)
}

// NTLMAuthHeader extracts NTLM base64 data from Authorization header.
func NTLMAuthHeader(r string) string {
	const prefix = "NTLM "
	if len(r) > len(prefix) && strings.EqualFold(r[:len(prefix)], prefix) {
		return strings.TrimSpace(r[len(prefix):])
	}
	return ""
}

// NTLMAuthUsername tries to extract the authenticated username from an NTLM Authorization header.
// Returns username and whether this is an NTLM request at all.
func NTLMAuthUsername(authHeader string) (username string, isNTLM bool) {
	data := NTLMAuthHeader(authHeader)
	if data == "" {
		return "", false
	}
	isNTLM = true
	raw, err := base64.StdEncoding.DecodeString(data)
	if err != nil || len(raw) < 12 || string(raw[:8]) != string(ntlmSignature) {
		return "", true
	}
	msgType := binary.LittleEndian.Uint32(raw[8:12])
	if msgType == ntlmAuthenticate {
		username = ParseNTLMAuthenticate(data)
	}
	// Type 1 → empty username, caller should send challenge
	return username, true
}

func NTLMChallengeHeader() string {
	return fmt.Sprintf("NTLM %s", NTLMChallenge())
}
