all: chat

chat: display.hs prompt.hs
	ghc --make -threaded display.hs
	ghc --make -threaded prompt.hs

.PHONY: clean
clean:
	@rm *.o *.hi
	@rm display prompt

