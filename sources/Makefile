all:
	make -C rng
	make -C lmapm

clean:
	make -C rng clean
	make -C lmapm clean

copy: all
	rm -f ../lib/rng.so
	cp rng/librng.so ../lib/rng.so
	rm -f ../lib/mapm.so
	cp lmapm/build/mapm.so ../lib/mapm.so
