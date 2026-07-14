PYTHON ?= python3
LATEXMK ?= latexmk

.PHONY: all artifacts clean distclean

all: artifacts main.pdf

artifacts:
	$(PYTHON) scripts/generate_artifacts.py --data-dir data --output-dir generated

main.pdf: main.tex references.bib generated/results-table.tex generated/passes-table.tex generated/trajectory.dat generated/trajectory-plot.tex
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error main.tex

clean:
	$(LATEXMK) -c main.tex

distclean: clean
	rm -f main.pdf
