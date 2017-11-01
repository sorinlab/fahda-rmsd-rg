# fahda-rmsd-rg

Root-mean-square Deviation (RMSD) & Radius of Gyration (R<sub>g</sub>) Calculations

## RMSD & R<sub>g</sub> calculation

Calculate RMSD & R<sub>g</sub> for each frame in all simulations and output to logfile. The script will not regenerate the `*.xvg` files if they already exist.

```bash
$ usegromacs33
$ ./calc-rmsd-rg.pl PROJ1797 index.ndx topol.gro output.log
$ head output.log
1797       0       1         0      0.034     11.335
1797       0       1       100      3.492     12.696
1797       0       1       200      3.266     12.475
1797       0       1       300      3.324     12.576
1797       0       1       400      3.330     12.642
...
```

## Usage

```bash
rmsd-rg-calc.pl <project_dir> <index.ndx> <topol.gro> <output.log>

    --clean-artifacts
        When specified the generated *.xvg files are removed after the
        script finishes.

    IMPORTANT:

    *   index.ndx and topol.gro must have absolute paths.

    *   call "usegromacs33" or similar before running this script.
```