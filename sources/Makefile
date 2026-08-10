all:
	make -C rng
	make -C lmapm
	make -C extutils
	cd dmath; cmake .
	make -C dmath

clean:
	make -C rng clean
	make -C lmapm clean
	make -C extutils clean
	make -C dmath clean

copy: all
# rng
	rm -f ../lib/rng.so
	cp rng/librng.so ../lib/rng.so
# mapm
	rm -f ../lib/mapm.so
	cp lmapm/build/mapm.so ../lib/mapm.so
# extutils
	rm -f ../lib/extutils.so
	cp extutils/extutils.so ../lib/extutils.so
# dmath
	rm -f ../lib/dmath.so
	cp dmath/libdmath.so ../lib/dmath.so
