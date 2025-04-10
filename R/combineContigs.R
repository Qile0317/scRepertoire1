# Adding Global Variables
# data('v_gene','j_gene', 'c_gene', 'd_gene')
utils::globalVariables(c("v_gene", "j_gene", "c_gene", "d_gene", "chain"))

heavy_lines <- c("IGH", "cdr3_aa1", "cdr3_nt1", "vgene1")
light_lines <- c("IGLC", "cdr3_aa2", "cdr3_nt2", "vgene2")
l_lines <- c("IGLct", "cdr3", "cdr3_nt", "v_gene")
k_lines <- c("IGKct", "cdr3", "cdr3_nt", "v_gene")
h_lines <- c("IGHct", "cdr3", "cdr3_nt", "v_gene")
tcr1_lines <- c("TCR1", "cdr3_aa1", "cdr3_nt1")
tcr2_lines <- c("TCR2", "cdr3_aa2", "cdr3_nt2")
data1_lines <- c("TCR1", "cdr3", "cdr3_nt")
data2_lines <- c("TCR2", "cdr3", "cdr3_nt")
CT_lines <- c("CTgene", "CTnt", "CTaa", "CTstrict")

utils::globalVariables(c("heavy_lines", "light_lines", "l_lines", "k_lines", 
            "h_lines", "tcr1_lines", "tcr2_lines", "data1_lines", 
            "data2_lines", "CT_lines"))

#' Combining the list of T Cell Receptor contigs
#'
#' This function consolidates a list of TCR sequencing results to the level of 
#' the individual cell barcodes. Using the samples and ID parameters, the 
#' function will add the strings as prefixes to prevent issues with repeated 
#' barcodes. The resulting new barcodes will need to match the Seurat or SCE 
#' object in order to use, \code{\link{combineExpression}}. Several 
#' levels of filtering exist - remove or filterMulti are parameters that 
#' control how  the function  deals with barcodes with multiple chains 
#' recovered.
#' 
#' @examples
#' combineTCR(contig_list, 
#'            samples = rep(c("PX", "PY", "PZ"), each=2), 
#'            ID = rep(c("P", "T"), 3))
#' 
#' @param df List of filtered contig annotations from 10x Genomics.
#' @param samples The labels of samples (required).
#' @param ID The additional sample labeling (optional).
#' @param removeNA This will remove any chain without values.
#' @param removeMulti This will remove barcodes with greater than 2 chains.
#' @param filterMulti This option will allow for the selection of the 2 
#' corresponding chains with the highest expression for a single barcode. 

#' @import dplyr
#' @export
#' @return List of clonotypes for individual cell barcodes
combineTCR <- function(df, 
                       samples = NULL, 
                       ID = NULL, 
                       removeNA = FALSE, 
                       removeMulti = FALSE, 
                       filterMulti = FALSE) {
    df <- checkList(df)
    df <- checkContigs(df)
    out <- NULL
    final <- NULL
    for (i in seq_along(df)) {
        if(c("chain") %in% colnames(df[[i]])) {
          df[[i]] <- subset(df[[i]], chain != "Multi")
        }
        if(c("productive") %in% colnames(df[[i]])) {
          df[[i]] <- subset(df[[i]], productive %in% c(TRUE, "TRUE", "True", "true"))
        }
        df[[i]]$sample <- samples[i]
        df[[i]]$ID <- ID[i]
        if (filterMulti == TRUE) { 
          df[[i]] <- filteringMulti(df[[i]]) 
          }
    }
    #Prevents error caused by list containing elements with 0 rows
    blank.rows <- which(unlist(lapply(df, nrow)) == 0)
    if(length(blank.rows) > 0) {
      df <- df[-blank.rows]
      if(!is.null(samples)) {
        samples <- samples[-blank.rows]
      }
      if(!is.null(ID)) {
        ID <- ID[-blank.rows]
      }
    }
    if (!is.null(samples)) {
        out <- modifyBarcodes(df, samples, ID)
    } else {
      out <- df
    }
    for (i in seq_along(out)) { 
        data2 <- out[[i]]
        data2 <- makeGenes(cellType = "T", data2)
        unique_df <- unique(data2$barcode)
        Con.df <- data.frame(matrix(NA, length(unique_df), 7))
        colnames(Con.df) <- c("barcode",tcr1_lines, tcr2_lines)
        Con.df$barcode <- unique_df
        Con.df <- parseTCR(Con.df, unique_df, data2)
        Con.df <- assignCT(cellType = "T", Con.df)
        Con.df[Con.df == "NA_NA" | Con.df == "NA_NA_NA_NA"] <- NA 
        data3 <- merge(data2[,-which(names(data2) %in% c("TCR1","TCR2"))], 
            Con.df, by = "barcode")
        if (!is.null(samples) & !is.null(ID)) {
            data3<-data3[,c("barcode","sample","ID",tcr1_lines,tcr2_lines,
                CT_lines)] }
        else if (!is.null(samples) & is.null(ID)) {
          data3<-data3[,c("barcode","sample",tcr1_lines,tcr2_lines,
                          CT_lines)] 
        }
        final[[i]] <- data3 
    }
    names <- NULL
    for (i in seq_along(samples)) { 
      if (!is.null(samples) & !is.null(ID)) {
          c <- paste(samples[i], "_", ID[i], sep="")
      } else if (!is.null(samples) & is.null(ID)) {
          c <- paste(samples[i], sep="")
      }
        names <- c(names, c)
    }
    names(final) <- names
    for (i in seq_along(final)){
        final[[i]]<-final[[i]][!duplicated(final[[i]]$barcode),]
        final[[i]]<-final[[i]][rowSums(is.na(final[[i]])) < 10, ]}
    if (removeNA == TRUE) { final <- removingNA(final)}
    if (removeMulti == TRUE) { final <- removingMulti(final) }
    return(final) }

#' Combining the list of B Cell Receptor contigs
#'
#' This function consolidates a list of BCR sequencing results to the level 
#' of the individual cell barcodes. Using the samples and ID parameters, 
#' the function will add the strings as prefixes to prevent issues with 
#' repeated barcodes. The resulting new barcodes will need to match the 
#' seurat or SCE object in order to use, 
#' \code{\link{combineExpression}}. Unlike combineTCR(), 
#' combineBCR produces a column CTstrict of an index of nucleotide sequence 
#' and the corresponding v-gene. This index automatically calculates 
#' the Levenshtein distance between sequences with the same V gene and will 
#' index sequences with <= 0.15 normalized Levenshtein distance with the same 
#' ID. After which, clonotype clusters are called using the igraph 
#' component() function. Clonotype that are clustered across multiple 
#' sequences will then be labeled with "LD" in the CTstrict header.
#'
#' @examples
#' #Data derived from the 10x Genomics intratumoral NSCLC B cells
#' BCR <- read.csv("https://www.borch.dev/uploads/contigs/b_contigs.csv")
#' combined <- combineBCR(BCR, samples = "Patient1", 
#' ID = "Time1", threshold = 0.85)
#' 
#' @param df List of filtered contig annotations from 10x Genomics.
#' @param samples The labels of samples (required).
#' @param ID The additional sample labeling (optional).
#' @param call.related.clones Use the nucleotide sequence and V gene to call related clones. 
#' Default is set to TRUE. FALSE will return a CTstrict or strict clonotype as V gene + amino acid sequence
#' @param threshold The normalized edit distance to consider. The higher the number the more 
#' similarity of sequence will be used for clustering.
#' @param removeNA This will remove any chain without values.
#' @param removeMulti This will remove barcodes with greater than 2 chains.
#' @param filterMulti This option will allow for the selection of the highest-expressing light and heavy 
#' chains, if not calling related clones.
#' @import dplyr
#' @export
#' @return List of clonotypes for individual cell barcodes
combineBCR <- function(df, 
                       samples = NULL, 
                       ID = NULL, 
                       call.related.clones = TRUE,
                       threshold = 0.85,
                       removeNA = FALSE, 
                       removeMulti = FALSE,
                       filterMulti = TRUE) {
    df <- checkList(df)
    df <- checkContigs(df)
    out <- NULL
    final <- list()
    chain1 <- "heavy"
    chain2 <- "light"
    for (i in seq_along(df)) {
        df[[i]] <- subset(df[[i]], chain %in% c("IGH", "IGK", "IGL"))
        #df[[i]] <- df[[i]] %>% group_by(barcode,chain) %>% slice_max(n=1,order_by=reads, with_ties = FALSE)
        df[[i]]$sample <- samples[i]
        df[[i]]$ID <- ID[i]
        if (filterMulti) {
                    # Keep IGH / IGK / IGL info in save_chain
                    df[[i]]$save_chain <- df[[i]]$chain
                    # Collapse IGK and IGL chains
                    df[[i]]$chain <- ifelse(df[[i]]$chain=="IGH","IGH","IGLC")
                    df[[i]] <- filteringMulti(df[[i]])
                    # Get back IGK / IGL distinction
                    df[[i]]$chain <- df[[i]]$save_chain
                    df[[i]]$save_chain <- NULL
        }
    }
    if (!is.null(samples)) {
      out <- modifyBarcodes(df, samples, ID)
    } else {
      out <- df
    }
    for (i in seq_along(out)) { 
        data2 <- data.frame(out[[i]])
        data2 <- makeGenes(cellType = "B", data2)
        unique_df <- unique(data2$barcode)
        Con.df <- data.frame(matrix(NA, length(unique_df), 9))
        colnames(Con.df) <- c("barcode", heavy_lines, light_lines)
        Con.df$barcode <- unique_df
        Con.df <- parseBCR(Con.df, unique_df, data2)
        Con.df <- assignCT(cellType = "B", Con.df)
        data3<-Con.df %>% mutate(length1 = nchar(cdr3_nt1)) %>%
            mutate(length2 = nchar(cdr3_nt2))
        final[[i]] <- data3 
    }
    dictionary <- bind_rows(final)
    if(call.related.clones) {
      IGH <- lvCompare(dictionary, "IGH", "cdr3_nt1", threshold)
      IGLC <- lvCompare(dictionary, "IGLC", "cdr3_nt2", threshold)
    } 
    for(i in seq_along(final)) {
      if(call.related.clones) {
        final[[i]]<-merge(final[[i]],IGH,by.x="cdr3_nt1",by.y="IG",all.x=TRUE)
        final[[i]]<-merge(final[[i]],IGLC,by.x="cdr3_nt2",by.y="IG",all.x=TRUE)
        num <- ncol(final[[i]])
        final[[i]][,"CTstrict"] <- paste0(final[[i]][,num-1],".",
              final[[i]][,"vgene1"],"_",final[[i]][,num],".",final[[i]][,"vgene2"])
      } else {
        final[[i]][,"CTstrict"] <- paste0(final[[i]][,"vgene1"], ".", final[[i]][,"cdr3_aa1"], "_", final[[i]][,"vgene2"], ".", final[[i]][,"cdr3_aa2"])
      }
        final[[i]]$sample <- samples[i]
        final[[i]]$ID <- ID[i]
        final[[i]][final[[i]] == "NA_NA" | final[[i]] == "NA_NA_NA_NA"] <- NA 
        if (!is.null(sample) & !is.null(ID)) {
          final[[i]]<- final[[i]][, c("barcode", "sample", "ID", 
              heavy_lines[c(1,2,3)], light_lines[c(1,2,3)], CT_lines)]
          }
        else if (!is.null(sample) & is.null(ID)) {
          final[[i]]<- final[[i]][, c("barcode", "sample", 
                    heavy_lines[c(1,2,3)], light_lines[c(1,2,3)], CT_lines)]
        }
    }
    names <- NULL
    for (i in seq_along(samples)) { 
      if (!is.null(samples) & !is.null(ID)) {
        c <- paste(samples[i], "_", ID[i], sep="")
      } else if (!is.null(samples) & is.null(ID)) {
        c <- paste(samples[i], sep="")
      }
      names <- c(names, c)}
    names(final) <- names
    for (i in seq_along(final)) {
        final[[i]] <- final[[i]][!duplicated(final[[i]]$barcode),]
        final[[i]]<-final[[i]][rowSums(is.na(final[[i]])) < 10, ]}
    if (removeNA == TRUE) { final <- removingNA(final) }
    if (removeMulti == TRUE) { final <- removingMulti(final) }
    return(final) 
}

# Calculates the normalized Levenshtein Distance between the contig 
# nucleotide sequence.
#' @importFrom stringdist stringdistmatrix
#' @importFrom igraph graph_from_data_frame components
#' @importFrom dplyr bind_rows
lvCompare <- function(dictionary, gene, chain, threshold) {
    overlap <- NULL
    out <- NULL
    dictionary[dictionary == "None"] <- NA
    dictionary$v.gene <- stringr::str_split(dictionary[,gene], "[.]", simplify = TRUE)[,1]
    tmp <- na.omit(unique(dictionary[,c(chain, "v.gene")]))
    #chunking the sequences for distance by v.gene
    unique.v <- na.omit(unique(tmp$v.gene))
    edge.list <- list()
    
    edge.list <- lapply(unique.v, function(y) {
    #for(y in unique.v) {
      secondary.list <- NULL
      filtered_df <- tmp %>% filter(v.gene == y)
      filtered_df <- filtered_df[!is.na(filtered_df[,chain]),]
      nucleotides <- unique(filtered_df[,chain])
      if (length(nucleotides) > 1) {
        for (i in 1:(length(nucleotides) - 1)) {
          list <- NULL
          for (j in (i + 1):length(nucleotides)) {
            distance <- stringdist::stringdist(nucleotides[i], nucleotides[j], method = "lv")
            distance <- 1-distance/((nchar(nucleotides[i]) + nchar(nucleotides[j]))/2)
            
            if (!is.na(distance) & distance > threshold) {
              if(any(which(tmp[,chain] == nucleotides[j]) %!in% which(tmp[,chain] == nucleotides[i]))) {
                stored.positions <- which(tmp[,chain] == nucleotides[j])[which(tmp[,chain] == nucleotides[j]) %!in% which(tmp[,chain] == nucleotides[i])]
                # Store this pair in the edge list that is not the same chain
                 ex.grid <- expand.grid(which(tmp[,chain] == nucleotides[i]), stored.positions)
                 colnames(ex.grid) <- c("from", "to")
                 list[[j]] <- ex.grid
                 
                 
              }
            }      
          }
          #Remove any NULL or 0 list elements
          if(length(list) > 0) {
            list <-  list[-which(unlist(lapply(list, is.null)))]
            list <-  list[lapply(list,length)>0]
            list <- bind_rows(list) %>% as.data.frame()
            secondary.list[[i]] <- list
          }
        }
        #Remove any NULL or 0 list elements
        if(length(secondary.list) > 0) {
          secondary.list <-  secondary.list[-which(unlist(lapply(secondary.list, is.null)))]
          secondary.list <-  secondary.list[lapply(secondary.list,length)>0]
        }
      }
      secondary.list
    })
    #Remove NULL elements and make data.frame
    edge.list = edge.list[-which(sapply(edge.list, is.null))]
    edge.list <- bind_rows(edge.list)
    
    if (nrow(edge.list) > 0) { 
      edge.list <- unique(edge.list)
      g <- graph_from_data_frame(edge.list)
      components <- components(g, mode = c("weak"))
      out <- data.frame("cluster" = components$membership, 
                        "filtered" = names(components$membership))
      filter <- which(table(out$cluster) > 1)
      out <- subset(out, cluster %in% filter)
      if(nrow(out) > 1) {
        out$cluster <- paste0(gene, ":LD", ".", out$cluster)
        out$filtered <- tmp[,1][as.numeric(out$filtered)]
        uni_IG <- as.data.frame(unique(tmp[,1][tmp[,1] %!in% out$filtered]))
      }
    } else {
      uni_IG <- as.data.frame(unique(tmp[,1]))
    }
    colnames(uni_IG)[1] <- "filtered"
    if (nrow(uni_IG) > 0) {
      uni_IG$cluster <- paste0(gene, ".", seq_len(nrow(uni_IG)))
    }
    output <- rbind.data.frame(out, uni_IG)
    colnames(output) <- c("Hclonotype", "IG")
    return(output)
}
