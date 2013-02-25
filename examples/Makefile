all: chat

chat: display.hs prompt.hs
	ghc --make -threaded display.hs
	ghc --make -threaded prompt.hs

.PHONY: clean
clean:
	-rm -f *.o *.hi
	-rm -f display prompt

