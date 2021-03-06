#'
#' ### MODEL
#'
#' @noRd
fit_autoenc <- function(fds, type=currentType(fds), q_guess=round(ncol(fds)/4),
                    correction, noiseRatio=0.5, BPPARAM=bpparam(),
                    iterations=3, verbose=FALSE){

    message(paste(date(), "; q:", q_guess, "; noise: ", noiseRatio))

    # setup object
    currentType(fds) <- type

    # train AE
    fds <- fit(fds, type=type, q=q_guess, correction=correction,
            iterations=iterations, 
            verbose=verbose, BPPARAM=BPPARAM)
    curLoss <- metadata(fds)[[paste0('loss_', type)]]
    curLoss <- mean(curLoss[,ncol(curLoss)])

    return(list(fds=fds, evaluation=curLoss))
}

predict_outliers <- function(fds, type, correction, BPPARAM){

    fds <- calculatePvalues(fds, type=type, correction=correction,
            BPPARAM=BPPARAM)

    return(fds)
}

eval_prot <- function(fds, type){
    index <- getSiteIndex(fds, type)
    idx   <- !duplicated(index)

    scores <- -as.vector(pVals(fds, type=type)[idx,])

    dt <- cbind(data.table(id=index),
            as.data.table(assay(fds, paste0("trueOutliers_", type))))
    setkey(dt, id)
    labels <- as.vector(vapply(samples(fds), function(i){
        dttmp <- dt[,any(get(i) != 0),by=id]
        setkey(dttmp, id)
        dttmp[J(unique(index)), V1]
    }, FUN.VALUE=logical(length(unique(index))) ) ) + 0

    if(any(is.na(scores))){
        warning(sum(is.na(scores)), " P-values where NAs.")
        scores[is.na(scores)] <- min(scores, na.rm=TRUE)-1
    }
    pr <- pr.curve(scores, weights.class0=labels)
    pr

    return(pr$auc.integral)
}


findEncodingDim <- function(i, fds, type, params, correction,
                    internalBPPARAM=1, iterations){
    iBPPARAM <- getBPParam(internalBPPARAM)

    q_guess    <- params[i, "q"]
    noiseRatio <- params[i, "noise"]
    message(paste(i, ";\t", q_guess, ";\t", noiseRatio))
    correction <- getHyperOptimCorrectionMethod(correction)

    res_fit <- fit_autoenc(fds=fds, type=type, q_guess=q_guess,
            correction=correction, 
            noiseRatio=noiseRatio, BPPARAM=iBPPARAM,
            iterations=iterations)
    res_pvals <- predict_outliers(res_fit$fds, correction=correction,
            type=type, BPPARAM=iBPPARAM)
    evals <- eval_prot(res_pvals, type=type)

    return(list(q=q_guess, noiseRatio=noiseRatio, loss=res_fit$evaluation, 
                aroc=evals))
}

#'
#' Find optimal encoding dimension
#'
#' Finds the optimal encoding dimension by injecting artificial splicing outlier
#' ratios while maximizing the precision-recall curve.
#'
#' @inheritParams fit
#' @param q_param Vector specifying which values of q should be tested
#' @param noise_param Vector specifying which noise levels should be tested.
#' @param setSubset The size of the subset of the most variable introns that 
#' should be used for the hyperparameter optimization.
#' @param internalThreads The number of threads used internally.
#' @param injectFreq The frequency with which outliers are injected into the 
#' data.
#' @param plot If \code{TRUE}, a plot of the area under the curve and the 
#' model loss for each evaluated parameter combination will be displayed after 
#' the hyperparameter optimization finishes.
#' 
#' @return FraseRDataSet
#'
#' @examples
#'   # generate data
#'   fds <- createTestFraseRDataSet()
#'   
#'   # run hyperparameter optimization
#'   fds <- optimHyperParams(fds, type="psi5", correction="PCA")
#'   
#'   # get estimated optimal dimension of the latent space
#'   bestQ(fds, type="psi5")
#'   
#'   # plot the AUC for the different encoding dimensions tested
#'   plotEncDimSearch(fds, type="psi5")
#'
#' @export
optimHyperParams <- function(fds, type, correction="PCA",
                    q_param=seq(2, min(40, ncol(fds)), by=3),
                    noise_param=0, minDeltaPsi=0.1,
                    iterations=5, setSubset=15000, injectFreq=1e-2,
                    BPPARAM=bpparam(), internalThreads=1, plot=TRUE){
    if(isFALSE(needsHyperOpt(correction))){
        message(date(), ": For correction '", correction, "' no hyper paramter",
                "optimization is needed.")
        data <- data.table(q=NA, noise=0, eval=1, aroc=1)
        hyperParams(fds, type=type) <- data
        return(fds)
    }

    #
    # put the most important stuff into memory
    #
    currentType(fds) <- type
    counts(fds, type=type, side="other", HDF5=FALSE) <-
            as.matrix(counts(fds, type=type, side="other"))
    counts(fds, type=type, side="ofInterest", HDF5=FALSE) <-
            as.matrix(counts(fds, type=type, side="ofInterest"))

    #
    # remove non variable and low abundance junctions
    #
    j2keepVa <- variableJunctions(fds, type, minDeltaPsi)
    j2keepDP <- rowQuantiles(K(fds, type), probs=0.75) >= 10
    j2keep <- j2keepDP & j2keepVa
    message("dPsi filter:", pasteTable(j2keep))
    # TODO fds <- fds[j2keep,,by=type]

    # ensure that subset size is not larger that number of introns/splice sites
    setSubset <- pmin(setSubset, nrow(K(fds, type)))
    
    optData <- data.table()
    for(nsub in setSubset){
        # subset for finding encoding dimensions
        # most variable functions + random subset for decoder
        exMask <- subsetKMostVariableJunctions(fds[j2keep,,by=type], type, nsub)
        j2keep[j2keep==TRUE] <- exMask

        # keep n most variable junctions + random subset
        j2keep <- j2keep | sample(c(TRUE, FALSE), length(j2keep), replace=TRUE,
                prob=c(nsub/length(j2keep), 1 - nsub/length(j2keep)))
        message("Exclusion matrix: ", pasteTable(j2keep))

        # make copy for testing
        fds_copy <- fds
        dontWriteHDF5(fds_copy) <- TRUE
        featureExclusionMask(fds_copy) <- j2keep
        fds_copy <- fds_copy[j2keep,,by=type]
        currentType(fds_copy) <- type

        # inject outliers
        fds_copy <- injectOutliers(fds_copy, type=type, freq=injectFreq,
                minDpsi=minDeltaPsi, method="samplePSI")
        
        if(sum(getAssayMatrix(fds_copy, type=type, "trueOutliers") != 0) == 0){
            warning(paste0("No outliers could be injected so the ", 
                            "hyperparameter optimization could not run. ", 
                            "Possible reason: too few junctions in the data."))
            return(fds)
        }

        # remove unneeded blocks to save memory
        a2rm <- paste(sep="_", c("originalCounts", "originalOtherCounts"),
                rep(psiTypes, 2))
        for(a in a2rm){
            assay(fds_copy, a) <- NULL
        }
        metadata(fds_copy) <- list()
        gc()

        # reset lost important values
        currentType(fds_copy) <- type
        dontWriteHDF5(fds_copy) <- TRUE

        # run hyper parameter optimization
        params <- expand.grid(q=q_param, noise=noise_param)
        message(date(), ": Run hyper optimization with ", nrow(params), 
                " options.")
        res <- bplapply(seq_len(nrow(params)), findEncodingDim, fds=fds_copy, 
                        type=type,
                        iterations=iterations, params=params, 
                        correction=correction,
                        BPPARAM=BPPARAM, 
                        internalBPPARAM=internalThreads)

        data <- data.table(
            q=vapply(res, "[[", "q", FUN.VALUE=numeric(1)),
            noise=vapply(res, "[[", "noiseRatio", FUN.VALUE=numeric(1)),
            nsubset=nsub,
            eval=vapply(res, "[[", "loss", FUN.VALUE=numeric(1)),
            aroc=vapply(res, "[[", "aroc", FUN.VALUE=numeric(1)))

        optData <- rbind(optData, data)
    }

    hyperParams(fds, type=type) <- optData
    if(isTRUE(plot)){
        print(plotEncDimSearch(fds, type=type, plotType="auc"))
    }
    return(fds)
}

