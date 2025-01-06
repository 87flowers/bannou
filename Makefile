.DEFAULT_GOAL := default

ifndef EXE
EXE=bannou
endif

default:
	zig build-exe --name $(EXE) -fllvm -flto -fstrip -static -target native -O ReleaseFast src/main.zig
