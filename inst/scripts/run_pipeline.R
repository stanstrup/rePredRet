#!/usr/bin/env Rscript
# Practical pipeline: existing build_all_models + JSON export optimization
# Skip complex furrr setup, use what we know works

message("\n")
message("╔════════════════════════════════════════════════════════╗")
message("║  rePredRet: PRACTICAL PIPELINE                         ║")
message("║  • Use existing build_all_models (proven to work)      ║")
message("║  • Add JSON export (skip HTML plots)                   ║")
message("║  • With build cache & resume capability                ║")
message("╚════════════════════════════════════════════════════════╝")
message("\n")

# Package is installed by CI workflow, no need to load_all()

# Load data (cached locally)
message("Loading RepoRT data...")
report_cache_dir <- file.path(getwd(), "RepoRT_data")
if (!dir.exists(report_cache_dir)) {
  dir.create(report_cache_dir, recursive = TRUE)
}
report_path <- download_report(dest_dir = report_cache_dir, overwrite = FALSE)
report_data <- load_report_data(report_path, method_types = c("RP"))
message("  ✓ Loaded ", length(report_data$datasets), " datasets\n")

# Setup output directory
output_dir <- file.path(getwd(), "website", "data", "models")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

message("Building all models (fast_ci method, no HTML plots)...")
message("Output: ", output_dir, "\n")

start_time <- Sys.time()

# Use existing build_all_models with export_dir
results <- build_all_models(
  report_data = report_data,
  min_compounds = 10,
  method = "fast_ci",
  alpha = 0.05,
  n_cores = parallel::detectCores(),
  method_match = TRUE,
  export_dir = output_dir,
  save_plots = FALSE  # KEY: Don't generate HTML plots
)

elapsed <- difftime(Sys.time(), start_time, units = "secs")

# Results
models <- results$models
index <- results$index

message("\n")
message("═══════════════════════════════════════════════════════════")
message("PIPELINE COMPLETE!")
message("═══════════════════════════════════════════════════════════\n")

n_successful <- nrow(index)
n_total <- length(models)

message("Summary:")
message("  Total model pairs: ", n_total)
message("  Successful models: ", n_successful)
message("  Success rate: ", round(n_successful/n_total*100, 1), "%")
message("  Total runtime: ", round(as.numeric(elapsed)/60, 1), " minutes\n")

if (n_successful > 0) {
  message("Statistics:")
  message("  Median PI width: ", round(median(index$median_ci_width, na.rm=TRUE), 3))
  message("  Mean PI width: ", round(mean(index$mean_ci_width, na.rm=TRUE), 3))
  message("  Median error: ", round(median(index$median_error, na.rm=TRUE), 3))
  
  # Save index
  write.csv(index, file.path(output_dir, "model_index.csv"), row.names = FALSE)
  message("\n✓ Model index saved\n")
}

message("═══════════════════════════════════════════════════════════")
message("Open website/model_viewer.html to explore models!")
message("═══════════════════════════════════════════════════════════\n")
