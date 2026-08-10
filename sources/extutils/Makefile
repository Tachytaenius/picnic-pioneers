all:
	gcc -c -fpic extutils.c -o extutils.o
	gcc -shared extutils.o -o extutils.so

clean:
	rm -f extutils.o extutils.so
