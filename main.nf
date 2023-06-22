/* 
 *   An assembly pipeline in Nextflow DSL2
 *   -----------------------------------------

 == V6 ==
 Added MLST support
 and optional assembler (Unicycler)

 */

/* 
 *   Input parameters 
 */
include { validateParameters; paramsHelp; paramsSummaryLog; fromSamplesheet } from 'plugin/nf-validation'

params.reads = "$baseDir/data/*_R{1,2}.fastq.gz"
params.outdir = "$baseDir/denovo"
params.unicycler = false
/*
  Import processes from external files
  It is common to name processes with UPPERCASE strings, to make
  the program more readable (this is of course not mandatory)
*/
include { FASTP; MULTIQC } from './modules/qc'
include { SHOVILL; UNICYCLER; PROKKA; QUAST } from './modules/assembly'
include { ABRICATE; ABRICATE_SUMMARY } from './modules/amr'
include { MLST; MLST_SUMMARY } from './modules/misc'

/* 
 *   DSL2 allows to reuse channels
 */
reads = Channel
        .fromFilePairs(params.reads, checkIfExists: true)

        
// Print help message, supply typical command line usage for the pipeline
if (params.help) {
   log.info paramsHelp("nextflow run my_pipeline --input input_file.csv")
   exit 0
}

// Validate input parameters
validateParameters()

// Print summary of supplied parameters
log.info paramsSummaryLog(workflow)

workflow {
    ch_multiqc = Channel.empty()

    if (!params.skip_qc) {
      FASTP( reads )
      ch_fastp_reads = FASTP.out.reads
      ch_multiqc = ch_multiqc.mix(FASTP.out.json).ifEmpty([])
    } else {
      ch_fastp_reads = reads
    }
    

    if (params.unicycler) {
      CONTIGS = UNICYCLER( ch_fastp_reads )
    } else {
      CONTIGS = SHOVILL( ch_fastp_reads  )
    }
    
    // AMR
    if (!params.skip_amr) {
      ABRICATE( CONTIGS )
      ABRICATE_SUMMARY( ABRICATE.out.map{it -> it[1]}.collect() )
      ch_multiqc = ch_multiqc.mix( ABRICATE_SUMMARY.out.multiqc ).ifEmpty([])
    }
    
    // Annotation
    if (!params.skip_prokka) {
      PROKKA( CONTIGS )
      ch_multiqc = ch_multiqc.mix( PROKKA.out ).ifEmpty([])
    }
    
    
    // QUAST requires all the contigs to be in the same directory
    QUAST( CONTIGS.map{it -> it[1]}.collect() )
    ch_multiqc = ch_multiqc.mix( QUAST.out ).ifEmpty([])

    if (!params.mlst) {
      MLST(  CONTIGS.map{it -> it[1]}.collect() )    
      MLST_SUMMARY( MLST.out.tab )
      ch_multiqc = ch_multiqc.mix( MLST_SUMMARY.out ).ifEmpty([])
    }
    

    // Collect all the relevant file for MultiQC
    MULTIQC( ch_multiqc.collect() ) 
}