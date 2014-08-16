all: chat

chat: display.hs prompt.hs
	cabal exec ghc -- --make -threaded display.hs
	cabal exec ghc -- --make -threaded prompt.hs

.PHONY: clean
clean:
	-rm -f *.o *.hi
	-rm -f display prompt

