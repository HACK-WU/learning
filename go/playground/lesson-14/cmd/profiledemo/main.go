// Command profiledemo produces small local profiles for the lesson.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"runtime/pprof"
	"time"
)

var liveHeap [][]byte

func burnCPU(duration time.Duration) int {
	deadline := time.Now().Add(duration)
	checksum := 0
	for time.Now().Before(deadline) {
		for i := 0; i < 500; i++ {
			checksum = checksum*31 + i
		}
	}
	return checksum
}

func makeLiveHeap() {
	liveHeap = make([][]byte, 0, 256)
	for i := 0; i < 256; i++ {
		liveHeap = append(liveHeap, make([]byte, 4096))
	}
}

func writeProfile(path string, profile *pprof.Profile) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	return profile.WriteTo(file, 0)
}

func collectCPU(path string) (int, error) {
	file, err := os.Create(path)
	if err != nil {
		return 0, err
	}
	if err := pprof.StartCPUProfile(file); err != nil {
		_ = file.Close()
		return 0, err
	}
	checksum := burnCPU(900 * time.Millisecond)
	pprof.StopCPUProfile()
	if err := file.Close(); err != nil {
		return 0, err
	}
	return checksum, nil
}

func collectBlockProfile(path string) error {
	runtime.SetBlockProfileRate(1)
	defer runtime.SetBlockProfileRate(0)

	ready := make(chan struct{})
	done := make(chan struct{})
	go func() {
		<-ready
		close(done)
	}()
	time.Sleep(40 * time.Millisecond)
	close(ready)
	<-done

	return writeProfile(path, pprof.Lookup("block"))
}

func main() {
	outputDir := flag.String("out", "", "directory for profile files")
	flag.Parse()
	if *outputDir == "" {
		fmt.Fprintln(os.Stderr, "-out is required")
		os.Exit(2)
	}
	if err := os.MkdirAll(*outputDir, 0o755); err != nil {
		panic(err)
	}

	checksum, err := collectCPU(filepath.Join(*outputDir, "cpu.prof"))
	if err != nil {
		panic(err)
	}
	makeLiveHeap()
	runtime.GC()
	if err := writeProfile(filepath.Join(*outputDir, "heap.prof"), pprof.Lookup("heap")); err != nil {
		panic(err)
	}

	never := make(chan struct{})
	go func() {
		<-never
	}()
	time.Sleep(30 * time.Millisecond)
	if err := writeProfile(filepath.Join(*outputDir, "goroutine.prof"), pprof.Lookup("goroutine")); err != nil {
		panic(err)
	}
	if err := collectBlockProfile(filepath.Join(*outputDir, "block.prof")); err != nil {
		panic(err)
	}

	runtime.GC()
	leakProfile := pprof.Lookup("goroutineleak")
	if leakProfile == nil {
		panic("goroutineleak profile is unavailable")
	}
	if err := writeProfile(filepath.Join(*outputDir, "goroutineleak.prof"), leakProfile); err != nil {
		panic(err)
	}

	fmt.Printf("checksum=%d\n", checksum)
	fmt.Println("profiles=cpu,heap,goroutine,block,goroutineleak")
}
