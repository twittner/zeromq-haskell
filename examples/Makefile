all: chat poll

chat: display.hs prompt.hs
	ghc --make -threaded display.hs
	ghc --make -threaded prompt.hs

poll: poll.hs
	ghc --make -threaded poll.hs

.PHONY: clean
clean:
	@rm *.o *.hi
	@rm display prompt poll

