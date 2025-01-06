.DEFAULT_GOAL := default

ifndef EXE
EXE=bannou
endif

default:
	zig build-exe --name $(EXE) -fllvm -flto -fstrip -fno-incremental -static -target native -O ReleaseFast src/main.zig
