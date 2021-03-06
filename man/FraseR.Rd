% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/Fraser-pipeline.R
\name{FraseR}
\alias{FraseR}
\title{FraseR: Find RAre Splicing Events in RNA-seq data}
\usage{
FraseR(
  fds,
  q,
  correction = c("PCA", "PCA-BB-Decoder", "AE-weighted", "AE", "BB"),
  iterations = 15,
  BPPARAM = bpparam(),
  ...
)
}
\arguments{
\item{fds}{A FraseRDataSet object}

\item{q}{The encoding dimensions to be used during the fitting proceadure.
If a named vector is provided it is used for the different
splicing types.}

\item{correction}{The method that should be used to correct for confounders.}

\item{iterations}{The maximal number of iterations. When the autoencoder has 
not yet converged after these number of iterations, the fit stops anyway.}

\item{BPPARAM}{A BiocParallel object to run the computation in parallel}

\item{...}{Additional parameters passed on to the internal fit function}
}
\value{
FraseRDataSet
}
\description{
The FraseR function runs the default FraseR pipeline combining the fit,
the computation of Z scores and p values as well as the delta-PSI values.
}
\details{
All computed values are returned as an FraseRDataSet object. To have
more control over each analysis step, one can call each function separately.
\itemize{
    \item \code{fit} to control for confounding effects and fit the beta 
    binomial model parameters, see \code{?fit} for details
    \item \code{calculatePvalues} to calculate the nominal p values, see 
    \code{?calculatePvalues} for details
    \item \code{calculatePadjValues} to calculate adjusted p values, see 
    \code{?calculatePadjValues} for details
    \item \code{calculateZscore} to calculate the Z scores, see 
    \code{?calculateZscore} for details
}

Available methods to correct for the confounders are currently: a denoising 
autoencoder with a BB loss ("AE" and "AE-weighted"), PCA ("PCA"), a hybrid 
approach where PCA is used to fit the latent space and then the decoder of 
the autoencoder is fit using the BB loss ("PCA-BB-Decoder"). Although not 
recommended, it is also possible to directly fit the BB distrbution to the 
raw counts ("BB").
}
\examples{
   # preprocessing
   fds <- createTestFraseRDataSet()
  
   # when running FRASER on a real dataset, one should run the following 
   # two commands first (not run here to make the example run faster)
   # fds <- calculatePSIValues(fds)
   # fds <- filterExpression(fds)

   # Run analysis pipeline: fits distribution and calculates p values
   fds <- FraseR(fds, q=2, correction="PCA")
   fds

   # afterwards, the fitted fds-object can be saved and results can 
   # be extracted and visualized, see ?saveFraseRDataSet, ?results and 
   # ?plotVolcano

}
\author{
Christian Mertes \email{mertes@in.tum.de}
}
