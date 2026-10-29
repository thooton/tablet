package appload

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "a", "state.json")
	if err := WriteFile(path, []byte("one"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := WriteFile(path, []byte("two"), 0o600); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil || string(data) != "two" {
		t.Fatalf("read %q, %v", data, err)
	}
	dir, _ := os.Stat(filepath.Dir(path))
	file, _ := os.Stat(path)
	if dir.Mode().Perm() != 0o700 || file.Mode().Perm() != 0o600 {
		t.Fatalf("modes %v %v", dir.Mode(), file.Mode())
	}
	if _, err := os.Stat(path + ".tmp"); !os.IsNotExist(err) {
		t.Fatal("left its temporary file")
	}
}
