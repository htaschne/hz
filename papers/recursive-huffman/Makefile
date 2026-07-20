PYTHON ?= python3
LATEXMK ?= latexmk

.PHONY: all artifacts clean distclean

all: artifacts paper.pdf

artifacts:
	$(PYTHON) scripts/generate_artifacts.py --data-dir artifacts/data --tables-dir tables --figures-dir figures

paper.pdf: paper.tex references.bib tables/results-table.tex tables/passes-table.tex figures/trajectory.dat figures/trajectory-plot.tex
	$(LATEXMK) -pdf -interaction=nonstopmode -halt-on-error paper.tex

clean:
	$(LATEXMK) -c paper.tex

distclean: clean
	rm -f paper.pdf
