all: lat thr

lat: local_lat.hs remote_lat.hs
	ghc --make -threaded local_lat.hs
	ghc --make -threaded remote_lat.hs

thr: local_thr.hs remote_thr.hs
	ghc --make -threaded local_thr.hs
	ghc --make -threaded remote_thr.hs

.PHONY: clean
clean:
	-rm -f *.o *.hi
	-rm -f local_lat remote_lat local_thr remote_thr

