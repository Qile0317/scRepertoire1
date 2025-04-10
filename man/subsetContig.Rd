% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/processing.R
\name{subsetContig}
\alias{subsetContig}
\title{Subset the product of combineTCR() combineBCR() or expression2List()}
\usage{
subsetContig(df, name, variables = NULL)
}
\arguments{
\item{df}{The product of combineTCR(), combineBCR(), or expression2List().}

\item{name}{The column header you'd like to use to subset.}

\item{variables}{The values to subset by, must be in the names(df).}
}
\value{
list of contigs that have been filtered for the name parameter
}
\description{
This function allows for the subsetting of the product of combineTCR() 
combineBCR() or expression2List() by the name of the individual list 
element. In general the names of are samples + _ + ID, allowing 
for users to subset the product of combineTCR(), combineBCR(), 
or expression2List() across a string or individual name.
}
\examples{
x <- contig_list
combined <- combineTCR(x, rep(c("PX", "PY", "PZ"), each=2), 
rep(c("P", "T"), 3))
subset <- subsetContig(combined, name = "sample", variables = c("PX"))

}
