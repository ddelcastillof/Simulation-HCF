#!/bin/bash
# run_simulation.sbatch
# -----------------------------------------------------------------------------
# Worker script for the Honest Causal Forest Monte Carlo study. Runs ONE of the
# 36 independent simulation cells of Simulation_HCF.Rmd per array task, via
# run_combo.R. The #SBATCH resource directives below default to the MEDIUM tier;
# submit_all.sh overrides --array/--cpus-per-task/--mem/--time per cost tier.
#
# Submit everything (recommended):   ./submit_all.sh
# Or one tier by hand, e.g. large:   sbatch --array=6,12,18,24,30,36 \
#                                       --cpus-per-task=16 --mem=64G \
#                                       --time=72:00:00 run_simulation.sbatch
# -----------------------------------------------------------------------------
#SBATCH --job-name=hcf_sim
#SBATCH --array=1-36                  # default: all cells; submit_all.sh narrows per tier
#SBATCH --cpus-per-task=8             # DEFAULT (medium tier) -- TUNE after a test run
#SBATCH --mem=24G                     # DEFAULT (medium tier) -- TUNE after a test run
#SBATCH --time=24:00:00               # DEFAULT (medium tier) -- TUNE after a test run
#SBATCH --output=logs/sim_%A_%a.out
#SBATCH --error=logs/sim_%A_%a.err
#SBATCH --account=REPLACE_ME          # <-- your SLURM account
#SBATCH --partition=REPLACE_ME        # <-- your partition/queue
#SBATCH --mail-type=BEGIN,FAIL,END
#SBATCH --mail-user=ddelcast@uw.edu

set -uo pipefail

# ---- Conda env with the pinned R packages (grf 2.0.2, faux, dplyr, ...) ------
module purge
module load REPLACE_ME_CONDA_MODULE   # e.g. miniconda3 / miniforge; remove if conda is already on PATH
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate REPLACE_ME_ENV         # <-- your R conda env

# ---- Threading --------------------------------------------------------------
# grf grows its forest with its own std::thread pool (capped by the cgroup to the
# allocated CPUs, so more --cpus-per-task = faster). Pin BLAS/OpenMP to 1 to avoid
# nested oversubscription. grf is reproducible for a fixed seed regardless of
# thread count, so this does not affect results.
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

# Node-local scratch for temp files (purl tempfile, etc.).
export TMPDIR="${SLURM_TMPDIR:-/tmp}"

cd "${SLURM_SUBMIT_DIR}"
mkdir -p logs results

echo "Job ${SLURM_JOB_ID} (array ${SLURM_ARRAY_JOB_ID:-NA} task ${SLURM_ARRAY_TASK_ID:-NA}) on $(hostname)"
echo "Allocated CPUs: ${SLURM_CPUS_PER_TASK:-?}"
echo "R: $(which R)"; R --version | head -n 1

# Run exactly one of the 36 cells, selected by the array task id.
Rscript run_combo.R "${SLURM_ARRAY_TASK_ID}" "Simulation_HCF.Rmd" "results"
status=$?
echo "run_combo.R (task ${SLURM_ARRAY_TASK_ID:-NA}) exit status: $status"
exit $status