# adapted from https://github.com/JonathanHallstrom/pawnocchio/blob/cb3b75af6cd2560b54d9de99df6a0e8abaeb495f/Makefile

.DEFAULT_GOAL := default

ifndef EXE
EXE=bannou
endif
ifeq ($(OS),Windows_NT)
MV=move .\zig-out\bin\bannou.exe $(EXE).exe
else
MV=mv ./zig-out/bin/bannou $(EXE)
endif

default:
	zig build --release=fast install
	@$(MV)
