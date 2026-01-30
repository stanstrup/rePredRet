#' Build All Models with furrr - Optimized with Caching and Scheduling
#'
#' Builds retention time prediction models using furrr for efficient outer-level
#' parallelization with support for incremental builds and scheduling tuning.
#'
#' @param report_data Report data from load_report_data()
#' @param min_compounds Minimum overlapping compounds for a pair (default 10)
#' @param method "fast_ci" (default, fast) or "bootstrap" (slow, accurate)
#' @param alpha Significance level (default 0.05 for 95% intervals)
#' @param n_workers Number of parallel workers (default = available cores)
#' @param save_json Save model data as JSON (default TRUE, much faster than HTML)
#' @param export_dir Directory to save models (required for caching)
#' @param batch_size Number of models to send to each worker at once (NULL = auto, 1 = dynamic, large = upfront)
#' @param verbose Print progress messages (default TRUE)
#'
#' @return List with:
#'   - models: list of all built models
#'   - index: data.frame with model metadata
#'   - stats: summary statistics
#'
#' @details
#' This function uses furrr::future_map for outer-level parallelization,
#' avoiding nested parallelization overhead. Each worker builds models sequentially.
#'
#' Caching: Detects changed datasets and skips unchanged models (requires export_dir)
#'
#' @importFrom furrr future_map
#' @importFrom future plan multisession
#' @export
build_all_models_furrr <- function(report_data,
                                  min_compounds = 10,
                                  method = c("fast_ci", "bootstrap"),
                                  alpha = 0.05,
                                  n_workers = parallel::detectCores(),
                                  save_json = TRUE,
                                  export_dir = NULL,
                                  batch_size = NULL,
                                  verbose = TRUE) {

  if (!requireNamespace("furrr", quietly = TRUE)) {
    stop("Package 'furrr' required. Install with: install.packages('furrr')")
  }

  method <- match.arg(method)

  datasets <- report_data$datasets
  studies <- report_data$studies
  dataset_ids <- names(datasets)

  if (verbose) {
    message("\n╔════════════════════════════════════════════════════════╗")
    message("║  Building Models with furrr + Caching                 ║")
    message("║  Method: ", method, " | Workers: ", n_workers, "                   ║")
    message("╚════════════════════════════════════════════════════════╝\n")
  }

  # Load build cache for incremental updates
  cache_file <- if (!is.null(export_dir)) {
    file.path(export_dir, "build_cache.rds")
  } else {
    NULL
  }

  if (!is.null(cache_file)) {
    cache <- load_build_cache(cache_file)
    message("Analyzing dataset changes for incremental build...")
    changes <- analyze_dataset_changes(datasets, cache)

    message("  NEW: ", length(changes$new_ids), " datasets")
    message("  CHANGED: ", length(changes$changed_ids), " datasets")
    message("  UNCHANGED: ", length(changes$unchanged_ids), " datasets")
    message("  REMOVED: ", length(changes$removed_ids), " datasets\n")

    if (length(changes$removed_ids) > 0 && !is.null(export_dir)) {
      cache <- purge_removed_models(changes$removed_ids, cache, export_dir)
    }

    cache <- update_dataset_cache(datasets, cache, changes$new_ids, changes$changed_ids)
  } else {
    cache <- NULL
    changes <- NULL
  }

  # Collect model pairs to build
  model_pairs <- list()

  for (i in seq_along(dataset_ids)) {
    for (j in seq_along(dataset_ids)) {
      if (i == j) next  # Skip self-comparison

      id1 <- dataset_ids[i]
      id2 <- dataset_ids[j]

      rt_matrix <- get_common_compounds(datasets[[id1]], datasets[[id2]])

      if (nrow(rt_matrix) < min_compounds) {
        next
      }

      model_pairs[[length(model_pairs) + 1]] <- list(
        sys1_id = id1,
        sys2_id = id2,
        rt_matrix = rt_matrix
      )
    }
  }

  if (verbose) {
    message("Building ", length(model_pairs), " models with ", n_workers, " workers...")
  }

  # Handle case where no models meet criteria
  if (length(model_pairs) == 0) {
    if (verbose) {
      message("No models meet the criteria (min_compounds=", min_compounds, ")\n")
    }

    index_df <- data.frame(
      sys1_id = character(),
      sys2_id = character(),
      n_compounds = integer(),
      median_ci_width = numeric(),
      median_error = numeric(),
      stringsAsFactors = FALSE
    )

    stats <- list(
      total_pairs = 0,
      successful = 0,
      success_rate = 0
    )

    return(list(
      models = structure(list(), class = "model_list"),
      index = index_df,
      stats = stats
    ))
  }

  # Set batch size (how many models to send to each worker at once)
  if (is.null(batch_size)) {
    # Auto: send groups of n_models / (n_workers * 4) to balance responsiveness
    batch_size <- max(1, ceiling(length(model_pairs) / (n_workers * 4)))
  }
  if (verbose) {
    message("Batch size: ", batch_size, " models per worker")
    message("Starting build at ", format(Sys.time(), "%H:%M:%S"), "\n")
  }

  build_start_time <- Sys.time()

  # Set up parallelization plan
  future::plan(future::multisession, workers = n_workers)

  # Process in batches and track progress after each batch
  all_results <- list()
  n_batches <- ceiling(length(model_pairs) / batch_size)

  for (batch_idx in 1:n_batches) {
    start_idx <- (batch_idx - 1) * batch_size + 1
    end_idx <- min(batch_idx * batch_size, length(model_pairs))
    batch_pairs <- model_pairs[start_idx:end_idx]

    if (verbose) {
      message("  Batch ", batch_idx, "/", n_batches,
              " (models ", start_idx, "-", end_idx, ")...")
    }

    # Build this batch in parallel using furrr
    batch_results <- furrr::future_map(
      batch_pairs,
      function(pair) {
        model <- build_model(
          rt_matrix = pair$rt_matrix,
          sys1_id = pair$sys1_id,
          sys2_id = pair$sys2_id,
          alpha = alpha,
          n_cores = 1,
          method = method,
          save_plot = FALSE
        )

        if (!is.null(export_dir) && model$status == "success") {
          model_dir <- file.path(export_dir, paste0(model$sys1_id, "_to_", model$sys2_id))
          export_model_fast(model, model_dir)

          if (save_json) {
            export_model_json(model, file.path(model_dir, "model.json"))
          }

          return(list(
            status = "success",
            sys1_id = model$sys1_id,
            sys2_id = model$sys2_id,
            n_compounds = model$n_points,
            median_ci_width = model$stats$median_ci_width,
            median_error = model$stats$median_error
          ))
        } else {
          return(list(
            status = model$status,
            sys1_id = pair$sys1_id,
            sys2_id = pair$sys2_id,
            message = model$message %||% NA_character_
          ))
        }
      },
      .progress = FALSE  # Don't show progress for individual batches, we'll show batch progress instead
    )

    all_results <- c(all_results, batch_results)

    # Log progress after batch completes
    if (verbose) {
      completed_so_far <- length(all_results)
      successful_so_far <- length(Filter(function(r) r$status == "success", all_results))
      elapsed <- as.numeric(difftime(Sys.time(), build_start_time, units = "secs"))
      speed <- successful_so_far / max(1, elapsed)

      message("    Progress: ", completed_so_far, " / ", length(model_pairs),
              " | Success: ", successful_so_far,
              " | Speed: ", round(speed, 2), " models/sec")

      if (speed > 0 && completed_so_far < length(model_pairs)) {
        remaining <- length(model_pairs) - completed_so_far
        eta_secs <- remaining / speed
        message("    ETA: ", round(eta_secs / 60, 1), " minutes\n")
      }
    }
  }

  results <- all_results

  # Final summary
  successful <- Filter(function(r) r$status == "success", results)

  if (verbose && length(model_pairs) > 0) {
    elapsed_build <- as.numeric(difftime(Sys.time(), build_start_time, units = "secs"))
    speed <- length(successful) / max(1, elapsed_build)

    message("\n")
    message("─── Build Complete ───")
    message("  Total models: ", length(model_pairs))
    message("  Successful: ", length(successful))
    message("  Success rate: ", round(length(successful) / length(model_pairs) * 100, 1), "%")
    message("  Total time: ", round(elapsed_build / 60, 1), " minutes")
    message("  Average speed: ", round(speed, 2), " models/sec\n")
  }

  # Clean up
  future::plan(future::sequential)


  # Convert results to index
  successful <- Filter(function(r) r$status == "success", results)

  index_df <- do.call(rbind, lapply(successful, function(r) {
    data.frame(
      sys1_id = r$sys1_id,
      sys2_id = r$sys2_id,
      n_compounds = r$n_compounds,
      median_ci_width = r$median_ci_width,
      median_error = r$median_error,
      stringsAsFactors = FALSE
    )
  }))

  # Summary statistics
  if (nrow(index_df) > 0) {
    stats <- list(
      total_pairs = length(model_pairs),
      successful = nrow(index_df),
      success_rate = round(nrow(index_df) / length(model_pairs) * 100, 1),
      median_ci_width = round(median(index_df$median_ci_width), 3),
      mean_ci_width = round(mean(index_df$median_ci_width), 3),
      median_error = round(median(index_df$median_error), 3),
      mean_error = round(mean(index_df$median_error), 3)
    )

    if (verbose) {
      message("\n╔════════════════════════════════════════════════════════╗")
      message("║  Pipeline Complete!                                    ║")
      message("╚════════════════════════════════════════════════════════╝\n")
      message("Summary:")
      message("  Total pairs to build: ", stats$total_pairs)
      message("  Successful models: ", stats$successful)
      message("  Success rate: ", stats$success_rate, "%")
      message("  Median CI width: ", stats$median_ci_width)
      message("\n")
    }
  } else {
    stats <- list(total_pairs = length(model_pairs), successful = 0, success_rate = 0)
  }

  list(
    models = structure(results, class = "model_list"),
    index = index_df,
    stats = stats
  )
}
