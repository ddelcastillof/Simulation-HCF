#!/usr/bin/env bash
# submit_all.sh
# -----------------------------------------------------------------------------
# Submit the 36 simulation cells as three tiered SLURM job arrays. sbatch CLI
# flags override the #SBATCH directives in run_simulation.sbatch, so the worker
# script stays single while each tier requests resources matched to its cost.
#
# Tiers (by nIndividuals x nTrees):
#   small  : all n=1000 cells + (n=10000, trees=200)        -> 18 cells
#   medium : (n=40000, trees=200) and (n=10000, trees=2000) -> 12 cells
#   large  : (n=40000, trees=2000)                          ->  6 cells
#
# SETUP (run ONCE on the login node, where there is internet access):
#   conda activate REPLACE_ME_ENV
#   Rscript -e 'webshot::install_phantomjs()'   # needed for the JPEG tables
#   SIM_NSIMS=5 Rscript run_combo.R 1           # smoke test: fast RCT cell
#   SIM_NSIMS=5 Rscript run_combo.R 13          # smoke test: observational cell
#
# Then submit the full run:   ./submit_all.sh
# -----------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p logs results

SBATCH=run_simulation.sbatch

# Small tier
sbatch --array=1,2,3,7,8,9,13,14,15,19,20,21,25,26,27,31,32,33 \
       --cpus-per-task=4  --mem=8G   --time=04:00:00 "$SBATCH"

# Medium tier
sbatch --array=4,5,10,11,16,17,22,23,28,29,34,35 \
       --cpus-per-task=8  --mem=24G  --time=24:00:00 "$SBATCH"

# Large tier
sbatch --array=6,12,18,24,30,36 \
       --cpus-per-task=16 --mem=64G  --time=72:00:00 "$SBATCH"

echo "Submitted small (18), medium (12), and large (6) tiers = 36 cells."