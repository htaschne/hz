LATEXMK ?= latexmk

.PHONY: all clean distclean smoke

all: paper.pdf

paper.pdf: paper.tex references.bib
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error paper.tex

smoke:
	./artifacts/reproduce.sh --smoke

clean:
	$(LATEXMK) -c paper.tex

distclean: clean
	rm -f paper.pdf
