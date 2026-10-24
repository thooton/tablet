//go:build !linux

package main

// lockFile is a no-op off Linux, where only the desktop emulator runs.
func lockFile(path string) (unlock func(), err error) {
	return func() {}, nil
}
