#!/usr/bin/env Rscript
# run_combo.R
# -----------------------------------------------------------------------------
# Run ONE simulation cell of Simulation_HCF.Rmd, selected by a SLURM array task
# id. The 36 cells in the paper are fully independent:
#   - tasks  1-12 : RCT,           combos 1-12
#   - tasks 13-24 : observational, combos 13-24, ortho = 1 (adjusted / AIPW)
#   - tasks 25-36 : observational, combos 13-24, ortho = 0 (unadjusted)
#
# Rather than copy the ~1,200 lines of function bodies (which would then need to
# be kept in sync), this driver extracts sim_cf_rct() / sim_cf_obs() straight
# from the .Rmd at run time and runs exactly one cell. The .Rmd stays the single
# source of truth and is never edited.
#
# Usage:
#   Rscript run_combo.R [task_id] [rmd_path] [out_dir]
#     task_id  : 1..36. Defaults to $SLURM_ARRAY_TASK_ID.
#     rmd_path : path to Simulation_HCF.Rmd. Default: "Simulation_HCF.Rmd".
#     out_dir  : where CSV/JPEG outputs are written. Default: ./results
#
# Env:
#   SIM_NSIMS : simulations per cell (default 1000). Set small (e.g. 5) for a
#               quick end-to-end smoke test before submitting the full run.
# -----------------------------------------------------------------------------

# Clear any inherited HTTP(S) proxy so downloads
Sys.setenv(http_proxy = "", https_proxy = "", HTTP_PROXY = "", HTTPS_PROXY = "")

if (!requireNamespace("knitr", quietly = TRUE)) {
  stop("knitr is required (ships with rmarkdown). Install it in your conda env.")
}

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(i) if (length(args) >= i && nzchar(args[i])) args[i] else NA_character_

# ---- Resolve which cell to run ----------------------------------------------
task_id <- get_arg(1)
if (is.na(task_id)) task_id <- Sys.getenv("SLURM_ARRAY_TASK_ID", unset = NA_character_)
task_id <- suppressWarnings(as.integer(task_id))
if (is.na(task_id) || task_id < 1L || task_id > 36L) {
  stop("task_id must be an integer in 1..36. Pass it as arg 1 or via ",
       "$SLURM_ARRAY_TASK_ID.")
}

rmd_path <- get_arg(2)
if (is.na(rmd_path)) rmd_path <- "Simulation_HCF.Rmd"
rmd_path <- normalizePath(rmd_path, mustWork = TRUE)

out_dir <- get_arg(3)
if (is.na(out_dir)) out_dir <- file.path(getwd(), "results")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
out_dir <- normalizePath(out_dir, mustWork = TRUE)

nSims <- suppressWarnings(as.integer(Sys.getenv("SIM_NSIMS", unset = "1000")))
if (is.na(nSims) || nSims < 1L) stop("SIM_NSIMS must be a positive integer.")

# ---- Build the 36-row job table (mirrors the .Rmd invocation chunks) ---------
# Within each setting/scenario the six size/tree cells appear in this fixed order:
cells <- data.frame(
  nIndividuals = c(1000, 1000, 10000, 10000, 40000, 40000),
  nTrees       = c( 200, 2000,   200,  2000,   200,  2000)
)
# Two scenarios, in order: (high corr, small CATEs) then (low corr, large CATEs).
scenarios <- data.frame(
  correlation = c("high", "low"),
  cates       = c("small", "large"),
  stringsAsFactors = FALSE
)
grid12 <- do.call(rbind, lapply(seq_len(nrow(scenarios)), function(s) {
  cbind(cells, scenarios[s, , drop = FALSE], row.names = NULL)
}))  # 12 rows: combos 1-12 / 13-24

rct  <- transform(grid12, fn = "rct", combo = 1:12, ortho = NA_integer_)
obs  <- transform(grid12, fn = "obs", combo = 13:24)
obs1 <- transform(obs, ortho = 1L)  # adjusted / doubly-robust
obs0 <- transform(obs, ortho = 0L)  # unadjusted

jobs <- rbind(rct, obs1, obs0)       # 36 rows; row index == task_id
rownames(jobs) <- NULL
stopifnot(nrow(jobs) == 36L)

job <- jobs[task_id, ]

# ---- Extract the simulation functions from the .Rmd -------------------------
# Both function-definition chunks are labelled `func`, so allow duplicate labels.
# purl() to a per-process temp file, drop the heavy `sim_cf_*( )` invocation lines
# and the repeated install_phantomjs() calls, then source the rest: this loads the
# libraries and defines sim_cf_rct() + sim_cf_obs() without running any cell.
options(knitr.duplicate.label = "allow")
src <- tempfile(fileext = ".R")
knitr::purl(rmd_path, output = src, documentation = 0L, quiet = TRUE)
code <- readLines(src)
code <- code[!grepl("^\\s*sim_cf_(rct|obs)\\s*\\(", code)]
code <- code[!grepl("install_phantomjs", code)]
writeLines(code, src)
source(src)

if (!all(c("sim_cf_rct", "sim_cf_obs") %in% ls())) {
  stop("Failed to extract sim_cf_rct/sim_cf_obs from ", rmd_path)
}

# JPEG diagnostic tables (save_kable) need PhantomJS via webshot. Best installed
# once on the login node; try here too, but never abort the run if offline.
if (requireNamespace("webshot", quietly = TRUE)) {
  phantom <- tryCatch(webshot:::find_phantom(), error = function(e) NULL)
  if (is.null(phantom)) try(webshot::install_phantomjs(), silent = TRUE)
}

# Make the (cosmetic) JPEG export non-fatal. In the .Rmd, save_kable() is called
# BEFORE the write.csv() of the results, so a missing PhantomJS would otherwise
# abort the whole cell and lose its CSVs. The sim functions call save_kable()
# unqualified, so R resolves it in the global env (here) before kableExtra's
# namespace -- this wrapper shadows it and turns an image failure into a warning.
# JPEGs are still produced normally whenever PhantomJS/webshot is available.
save_kable <- function(...) {
  ok <- tryCatch({ kableExtra::save_kable(...); TRUE },
                 error = function(e) {
                   message("[run_combo] save_kable skipped (no PhantomJS?): ",
                           conditionMessage(e))
                   FALSE
                 })
  invisible(ok)
}

# ---- Run the one cell -------------------------------------------------------
setwd(out_dir)

message(sprintf(
  "[run_combo] task=%d fn=%s combo=%d ortho=%s n=%d trees=%d corr=%s cates=%s nSims=%d out=%s",
  task_id, job$fn, job$combo, ifelse(is.na(job$ortho), "-", job$ortho),
  job$nIndividuals, job$nTrees, job$correlation, job$cates, nSims, out_dir
))
t0 <- Sys.time()

set.seed(930)  # data-generation seed (matches the .Rmd); forest seed is 112 inside grf
if (job$fn == "rct") {
  sim_cf_rct(nIndividuals = job$nIndividuals, nTrees = job$nTrees,
             correlation = job$correlation, cates = job$cates,
             nSims = nSims, combo = job$combo)
} else {
  sim_cf_obs(nIndividuals = job$nIndividuals, nTrees = job$nTrees,
             correlation = job$correlation, cates = job$cates,
             nSims = nSims, combo = job$combo, ortho = job$ortho)
}

message(sprintf("[run_combo] task=%d done in %s",
                task_id, format(round(difftime(Sys.time(), t0), 1))))