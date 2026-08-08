# This is used to get files that are needed to run the game.
# This doesn't build the project into AppImages or anything, that is makelove's job,
# but makelove does use this file.
# NOTE: The clean target in this makefile wipes makelove's build directory even though it doesn't make it.

all:
	make -C sources copy

clean:
	rm -f lib/*.so
	rm -rf makelove-build
	make -C sources clean
