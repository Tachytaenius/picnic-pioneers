all:
	make -C rng
	make -C lmapm
	cd dmath; cmake .
	make -C dmath

clean:
	make -C rng clean
	make -C lmapm clean
	make -C dmath clean

copy: all
# rng
	rm -f ../lib/rng.so
	cp rng/librng.so ../lib/rng.so
# mapm
	rm -f ../lib/mapm.so
	cp lmapm/build/mapm.so ../lib/mapm.so
# dmath
	rm -f ../lib/dmath.so
	cp dmath/libdmath.so ../lib/dmath.so
