#
#    sleuth: inspect your RNA-Seq with a pack of kallistos
#
#    Copyright (C) 2015  Harold Pimentel, Nicolas Bray, Pall Melsted, Lior Pachter
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

#' Print sleuth model
#'
#' Print a model that has been fit by sleuth
#'
#' @param obj a \code{sleuth_model} object
#' @return obj (invisible)
#' @export
print.sleuth_model <- function(obj) {
  cat('formula: ', deparse(obj$formula), '\n')
  cat('data modeled: ', obj$which_var, '\n')
  cat('transform sync\'ed: ', obj$transform_sync, '\n')
  cat('coefficients:\n')
  cat(paste0('\t', colnames(obj$design_matrix), '\n'))

  invisible(obj)
}

#' View which models have been fit
#'
#' @description  View which models have been fit. sleuth fits data using R formulas
#'
#' @param obj a sleuth object, containing kallisto results, usually made by sleuth_prep
#' @return an R formula showing what has been fit
#' @examples # imagine you have a set of samples from input and IP, and input has been set to intercept
#' models(so)
#' # [full]
#' # formula: ~condition
#' # coefficients:
#' #      (Intercept)
#' #      conditionIP
#' @export
models <- function(obj, ...) {
  UseMethod('models')
}

#' @export
models.sleuth <- function(obj, verbose = TRUE) {
  # TODO: output a new in between models for readability
  if (verbose) {
    for (x in names(obj$fits)) {
      cat('[ ', x, ' ]\n')
      models(obj$fits[[x]])
    }
  }


  invisible(obj$fits)
}

#' @export
models.sleuth_model <- function(obj) {
  print(obj)
}

#' Check Transform Sync Status of Sleuth Fits
#'
#' This method prints out the sync status for all fits of \code{sleuth} object
#' If the sleuth object's transform function was changed after sleuth_fit was used,
#' the user will need to redo sleuth_fit for any fits already done.
#'
#' @param obj a \code{sleuth} object.
#' @return a print out of each fit with the transform sync status.
#' @export
transform_status <- function(obj) {
  UseMethod('transform_status')
}

#' @export
transform_status.sleuth <- function(obj, verbose=TRUE) {
  if (is.null(obj$fits))
    stop("sleuth obj has no fits.")

  if (verbose) {
    for (x in names(obj$fits)) {
      cat('[ ', x, ' ]\n')
      models(obj$fits[[x]]$transform_synced)
    }
  }


  invisible(obj$fits)
}

#' @export
transform_status.sleuth_model <- function(obj) {
  print(obj$transform_synced)
}

#' Extract design matrix
#'
#' Accessor method for extracting a design matrix from a sleuth object
#'
#' @param obj a \code{sleuth} object
#' @param which_model a character string of the model
#' @return the \code{model.matrix} used to fit \code{which_model}
#' @export
design_matrix <- function(obj, which_model = 'full') {
  stopifnot( is(obj, 'sleuth') )

  if (!model_exists(obj, which_model)) {
    stop("'", which_model, "' does not exist in ", substitute(obj),
      ". Please check  models(", substitute(obj), ") for fitted models.")
  }

  obj[['fits']][[which_model]][['design_matrix']]
}

# Extract a test from a sleuth object
#
# Get the data frame from a sleuth object that corresponds to a specific test.
# Note: this function is not meant for users. The user facing version of this is \code{sleuth_results}
#
# @param obj a sleuth object
# @param label a string which is a label for the test you are trying to extract
# @param type the type of test (either: 'lrt', 'wt')
# @return a data frame with the relevant test information
get_test <- function(obj, label, type, model) {
  stopifnot( is(obj, 'sleuth') )
  stopifnot( type %in% c('lrt', 'wt') )

  res <- NULL
  if (type == 'lrt') {
    res <- obj$tests[[type]][[label]]
  } else {
    if ( missing(model) ) {
      stop('must specify a model with wald test')
    }
    res <- obj$tests[[type]][[model]][[label]]
  }

  if (is.null(res)) {
    stop("'", label, "' is not a valid label for a test.",
      " Please see valid models and tests using the functions 'models' and 'tests'.",
      " Remember to also correctly specify the test type.")
  }

  res
}

test_exists <- function(obj, label, type, model) {
  stopifnot( is(obj, 'sleuth') )
  stopifnot( type %in% c('lrt', 'wt') )

  tryCatch({
    temp <- get_test(obj, label, type, model)
  }, error = function(e) {
    return(FALSE)
  }, finally = function(x) {
      # intentionally empty
    })

  TRUE
}

# if type is 'lrt', return character vector tests
# else, return a list of character vectors.
# each element in the list corresponds to a particular model
list_tests <- function(obj, type) {
  stopifnot( is(obj, 'sleuth') )
  stopifnot( type %in% c('lrt', 'wt') )

  res <- NULL
  if (type == 'lrt') {
    res <- names(obj$tests[[type]])
  } else {
    res <- lapply(obj$tests[[type]], names)
    if ( length(res) == 0 ) {
      res <- NULL
    }
  }

  res
}

list_all_tests <- function(obj) {
  stopifnot( is(obj, 'sleuth') )

  list(lrt = list_tests(obj, 'lrt'), wt = list_tests(obj, 'wt'))
}

# Add a test to a sleuth object
#
# Add a test to a sleuth object. Note this function is not meant for users.
# @param obj a sleuth object
# @param test_table the data frame/data table you're interested inserting as the actual test
# @param label the label (name) you want to assign to this test
# @param type the type of test it is ('lrt' or 'wald')
# @return a sleuth object with the test added
add_test <- function(obj, test_table, label, type, model) {
  stopifnot( is(obj, 'sleuth') )
  stopifnot( type %in% c('lrt', 'wt') )

  if (type == 'wt' && missing(model)) {
    stop('if specifying a wald to test, must also specify a model.')
  }

  # store all tests in obj$tests
  if ( is.null(obj$tests) ) {
    obj$tests <- list()
  }

  if (type == 'lrt') {
    obj$tests[[type]][[label]] <- test_table
  } else {
    # wald test
    if ( is.null(obj$tests[[type]][[model]]) ) {
      obj$tests[[type]][[model]] <- list()
    }
    obj$tests[[type]][[model]][[label]] <- test_table
  }

  obj
}

#' @export
tests <- function(obj) {
  UseMethod('tests')
}

#' @export
tests.sleuth <- function(obj, lrt = TRUE, wt = TRUE) {
  if ( lrt ) {
    cat('~likelihood ratio tests:\n') # nolint
    cur_tests <- list_tests(obj, 'lrt')
    if (length(cur_tests) > 0) {
      for (test in cur_tests) {
        cat('\t', test, '\n', sep = '')
      }
    } else {
      cat('\tno tests found.\n')
    }
  }

  if ( lrt && wt ) {
    cat('\n')
  }

  if ( wt ) {
    cat('~wald tests:\n') # nolint
    cur_tests <- list_tests(obj, 'wt')
    if (length(cur_tests) > 0) {
      for (i in 1:length(cur_tests)) {
        cat('\t[ ', names(cur_tests)[i], ' ]\n', sep = '')
        for (j in 1:length(cur_tests[[i]])) {
          cat('\t', cur_tests[[i]][j], '\n', sep = '')
        }
      }
    } else {
      cat('\tno tests found.\n')
    }
  }


}

#' Extract Wald or Likelihood Ratio test results from a sleuth object
#'
#' This function extracts Wald or Likelihood Ratio test results from a sleuth object.
#'
#' @param obj a \code{sleuth} object
#' @param test a character string denoting the test to extract. Possible tests can be found by using \code{models(obj)}.
#' @param test_type 'wt' for Wald test or 'lrt' for Likelihood Ratio test.
#' @param which_model a character string denoting the model. If extracting a wald test, use the model name.
#'   Not used if extracting a likelihood ratio test.
#' @param rename_cols if \code{TRUE} will rename some columns to be shorter and
#'   consistent with the vignette
#' @param show_all if \code{TRUE} will show all transcripts (not only the ones
#' passing filters). The transcripts that do not pass filters will have
#' \code{NA} values in most columns.
#' @param pval_aggregate if \code{TRUE} and both \code{target_mapping} and \code{aggregation_column} were provided,
#' to \code{sleuth_prep}, use lancaster's method to aggregate p-values by the \code{aggregation_column}.
#' @param ... advanced options for sleuth_results. See details.
#'
#' @details The columns returned by this function will depend on a few factors: whether the test is a Wald test or
#'   Likelihood Ratio test, and whether \code{pval_aggregate} is \code{TRUE}.
#'
#'   The sleuth model is a measurement error in the response model. It attempts to segregate the variation due to
#'   the inference procedure by kallisto from the variation due to the covariates -- the biological and technical
#'   factors of the experiment (represented by the columns in \code{obj$sample_to_covariates}). For the Wald test,
#'   the 'b' column represents the estimate of the selected coefficient. In the default setting, it is analogous to,
#'   but not equivalent to, the fold-change. The transformed values are on the natural-log scale, and so the
#'   the estimated coefficient is also on the natural-log scale. This value is taking into account the estimated
#'   'inferential variance' estimated from the kallisto bootstraps.
#'
#'   If the user wishes to get gene-level results from this function, there are two ways of doing so:
#'
#'   \itemize{
#'     \item p-value aggregation mode: if \code{pval_aggregate} argument is TRUE, this function will
#'     aggregate the transcript-level p-values to the gene-level using the lancaster method. See below for advanced
#'     options related to this mode. This is the recommended way to do gene-level aggregation. See the paper
#'     
#'     \item count aggregation mode: This is the gene-level aggregation method introduced in sleuth version 0.28.1.
#'     This mode is activated if \code{obj$gene_mode} is \code{TRUE}. In this mode, the modeling and testing was done
#'     using aggregated counts (or TPMs), and so the results are same as for the transcript-level results, except the 
#'     target IDs are now gene IDs instead of transcript IDs.
#'   }
#' 
#'   An important note if \code{pval_aggregate} or the old \code{gene_mode} is \code{TRUE}: when combining the
#'   gene annotations from \code{obj$target_mapping}, all of the columns except for the transcript ID,
#'   \code{obj$target_mapping$target_id}, will be included. If there are transcript-level entries for any of the other
#'   columns, this will result in duplicate rows in the results table (usually an undesirable result).
#'
#' Here are advanced options for customizing the p-value aggregation procedure:
#'
#' \itemize{
#'   \item \code{weight_func}: if \code{pval_aggregate} is \code{TRUE}, then this is used to weight the p-values for
#'   lancaster's method. This function must take the observed means of the transcripts as the only defined argument.
#'   The default is \code{identity}.
#' }
#' 
#' @return If \code{pval_aggregate} is \code{FALSE}, returns a \code{data.frame} with the following columns:
#'
#' \itemize{
#' \item \code{target_id}: transcript name, e.g. "ENST#####" (dependent on the transcriptome used in kallisto).
#' If \code{gene_mode} is TRUE, this will instead be the IDs specified by the \code{obj$gene_column} from \code{obj$target_mapping}.
#' \item \code{...}: if there is a target mapping data frame, all of the annotations columns are added from
#' \code{obj$target_mapping} before the other columns.
#' \item \code{pval}: p-value of the chosen model
#' \item \code{qval}: false discovery rate adjusted p-value, using Benjamini-Hochberg (see \code{\link{p.adjust}})
#' \item \code{test_stat} (LRT only): Chi-squared test statistic (likelihood ratio test). Only seen with Likelihood Ratio test results.
#' \item \code{rss} (LRT only): the residual sum of squares under the "null model". Only seen with Likelihood Ratio test results.
#' \item \code{degrees_free} (LRT only): the degrees of freedom (equal to difference between the two models). Only seen with Likelihood Ratio test results.
#' \item \code{b} (Wald only): 'beta' value (effect size). Technically a biased estimator of the fold change. Only seen with Wald test results.
#' \item \code{se_b} (Wald only): standard error of the beta. Only seen with Wald test results.
#' \item \code{mean_obs}: mean of natural log counts of observations
#' \item \code{var_obs}: variance of observation
#' \item \code{tech_var}: technical variance of observation from the bootstraps (named 'sigma_q_sq' if rename_cols is \code{FALSE})
#' \item \code{sigma_sq}: raw estimator of the variance once the technical variance has been removed
#' \item \code{smooth_sigma_sq}: smooth regression fit for the shrinkage estimation
#' \item \code{final_simga_sq}: max(sigma_sq, smooth_sigma_sq); used for covariance estimation of beta
#'   (named 'smooth_sigma_sq_pmax' if rename_cols is \code{FALSE})
#' }
#'
#' If \code{pval_aggregate} is \code{TRUE}, returns a \code{data.frame} with the following columns:
#' 
#' \itemize{
#' \item \code{target_id}: gene ID specified by \code{obj$gene_column}, e.g. "ENSG#####" (dependent on the transcriptome
#'  used in kallisto).
#' \item \code{...}: all of the additional annotation columns (not \code{'target_id'} or \code{obj$gene_column}) are
#' added from \code{obj$target_mapping} before the other columns.
#' \item \code{num_aggregated_transcripts}: the number of transcripts aggregated for a given gene. These only include
#' filtered transcripts.
#' \item \code{sum_mean_obs_counts}: this is the sum of the mean observations across all filtered transcripts
#' within a gene. Note that the weighting function is applied before summing.
#' \item \code{pval}: the aggregated p-value calculated by the lancaster method. See the aggregation package for details.
#' \item \code{qval}: adjusted p-values using the Benchamini-Hochberg method.
#' }
#'
#' @seealso \code{\link{sleuth_wt}} and \code{\link{sleuth_lrt}} to compute tests, \code{\link{models}} to
#' view which models, \code{\link{tests}} to view which tests were performed (and can be extracted)
#' @examples
#' models(sleuth_obj) # for this example, assume the formula is ~condition,
#'                      and a coefficient is IP
#' results_table <- sleuth_results(sleuth_obj, 'conditionIP')
#' @export
sleuth_results <- function(obj, test, test_type = 'wt',
  which_model = 'full', rename_cols = TRUE, show_all = TRUE,
  pval_aggregate = obj$pval_aggregate,
  ...) {
  stopifnot( is(obj, 'sleuth') )

  extra_opts <- list(...)
  if ('weight_func' %in% names(extra_opts)) {
    weight_func <- extra_opts$weight_func
  } else {
    weight_func <- identity
  }
 
  if (test_type == 'wt' && !model_exists(obj, which_model)) {
    stop("'", which_model, "' does not exist in ", substitute(obj),
      ". Please check  models(", substitute(obj), ") for fitted models.")
  }
  # if ( which_model != 'lrt' && !model_exists(obj, which_model) ) {
  #   stop("'", which_model, "' does not exist in ", substitute(obj),
  #     ". Please check  models(", substitute(obj), ") for fitted models.")
  # }

  if (obj$gene_mode && pval_aggregate) {
    stop("This shouldn't happen. Please report this issue.")
  }

  if (pval_aggregate && is.null(obj$gene_column)) {
    stop("`aggregation_column` not set in `sleuth_prep()`.",
      " Please rerun sleuth_prep() with an aggregation column.")
  }

  if ( !is(test, 'character') ) {
    stop("'", substitute(test), "' is not a valid character.")
  }

  if ( length(test) != 1) {
    stop("'", substitute(test),
      "' is not a valid length. test must be of length one.")
  }

  res <- NULL
  if (test_type == 'lrt') {
    res <- get_test(obj, test, type = 'lrt')
    res <- dplyr::select(res,
      target_id,
      pval,
      qval,
      test_stat,
      rss,
      degrees_free,
      mean_obs,
      var_obs,
      sigma_q_sq,
      sigma_sq,
      smooth_sigma_sq,
      smooth_sigma_sq_pmax
      )
  } else {
    res <- get_test(obj, test, 'wt', which_model)
    res <- dplyr::select(res,
      target_id,
      pval,
      qval,
      b,
      se_b,
      mean_obs,
      var_obs,
      sigma_q_sq,
      sigma_sq,
      smooth_sigma_sq,
      smooth_sigma_sq_pmax
      )
  }

  res <- data.table::as.data.table(res)
  if (rename_cols) {
    res <- dplyr::rename(res,
      tech_var = sigma_q_sq,
      final_sigma_sq = smooth_sigma_sq_pmax
      )
  }

  if (pval_aggregate) {
    if (is.null(obj$target_mapping) ) {
      stop('Must provide transcript to gene mapping table in order to aggregate p-values. ',
           'Please rerun "sleuth_prep" using the "target_mapping" argument.')
    }
    if (length(which(weight_func(res$mean_obs) < 0)) > 0) {
      stop('The provided weighting function for the mean observations results in ',
           'negative values, which are not allowed for the lancaster method.')
    }
    t2g <- dplyr::select(obj$target_mapping, target_id, eval(obj$gene_column))
    res <- dplyr::right_join(data.table::as.data.table(t2g),
                             res, by = "target_id")
    res <- data.table::as.data.table(res)
    res <- res[, .(num_aggregated_transcripts = length(!is.na(pval)),
                   sum_mean_obs_counts = sum(weight_func(mean_obs), na.rm = TRUE),
                   pval = as.numeric(aggregation::lancaster(pval, weight_func(mean_obs)))),
               by = eval(obj$gene_column)]
    names(res)[names(res) == obj$gene_column] <- "target_id"
    res <- res[!is.na(res$target_id),]
    res <- res[, qval := p.adjust(pval, 'BH')]

  }

  if (show_all) {
    if (obj$gene_mode | pval_aggregate) {
      tids <- unique(dplyr::select(
        obj$target_mapping, eval(obj$gene_column)))
      by_col <- "target_id"
      names(by_col) <- obj$gene_column
    } else {
      tids <- adf(target_id = obj$kal[[1]]$abundance$target_id)
      by_col <- 'target_id'
    }
    res <- dplyr::left_join(
      data.table::as.data.table(tids),
      res,
      by = by_col
      )
    names(res)[names(res) == obj$gene_column] <- "target_id"
  }

  if (obj$gene_mode | pval_aggregate) {
    # after removing the target_id column
    # there are several redundant columns for each gene
    # this line gets the unique line for each gene
    target_mapping <- unique(dplyr::select(
                               obj$target_mapping,
                               -target_id))
    # this line uses dplyr's "left_join" syntax for "by"
    # to match "target_id" from the "res" table,
    # and the gene_column from the target_mapping table.
    by_col <- "target_id"
    names(by_col) <- obj$gene_column
    res <- dplyr::right_join(data.table::as.data.table(target_mapping),
                             res,
                             by = by_col)
    names(res)[names(res) == obj$gene_column] <- "target_id"
  } else if ( !is.null(obj$target_mapping) && !obj$gene_mode) {
    res <- dplyr::right_join(
      data.table::as.data.table(obj$target_mapping),
      res,
      by = 'target_id')
  }

  res <- as_df(res)

  dplyr::arrange(res, qval)
}

#' Extract a model from a sleuth object
#'
#' This function extracts the parameter estimates from a sleuth model after it
#' has been fit with \code{\link{sleuth_fit}}.
#' @param obj a sleuth object.
#' @param which_model a model fitted with \code{\link{sleuth_fit}}.
#' @return a data frame including a column for the target_id, the term (which coefficient),
#'         and the corresponding standard error.
#' @export
extract_model <- function(obj, which_model) {
  if (!model_exists(obj, which_model)) {
    stop("'", which_model, "' does not exist in ", substitute(obj),
      ". Please check  models(", substitute(obj), ") for fitted models.")
  }

  res <- lapply(seq_along(obj$fits[[which_model]]$models),
    function(i) {
      x <- obj$fits[[which_model]]$models[[i]]
      coefficients <- coef(x$ols_fit)
      list(
        target_id = rep_len(names(obj$fits[[which_model]]$models)[i], length(coefficients)),
        term = names(coefficients), estimate = coefficients,
        std_error = sqrt(diag(obj$fits[[which_model]]$beta_covars[[i]])))
    })
  dplyr::bind_rows(res)
}
