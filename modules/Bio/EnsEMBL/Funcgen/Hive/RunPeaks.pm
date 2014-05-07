
=pod 

=head1 NAME

Bio::EnsEMBL::Funcgen::Hive::RunPeaks

=head1 DESCRIPTION

This class runs a PeakCaller analysis and loads the results into the DB

=cut

package Bio::EnsEMBL::Funcgen::Hive::RunPeaks;

use warnings;
use strict;

use Bio::EnsEMBL::Utils::Exception         qw( throw );
use Bio::EnsEMBL::Funcgen::Utils::EFGUtils qw( run_system_cmd 
                                               scalars_to_objects
                                               validate_package_path );
use Bio::EnsEMBL::Funcgen::AnnotatedFeature;

use base qw( Bio::EnsEMBL::Funcgen::Hive::BaseDB );



#todo rename logic_names to be generic e.g. SWEmbl_tight
#then we can have different parameter sets between species

#todo Delegate to the peak analysis runnable, such that it is entirely independant of the hive
#this will require a standard interface
#and moving a lot of the fetch_input stuff in here
#rename this RunPeaks

#input_dir and work_dir can be separate
#such that we can't point to remote fastqs
#input_dir should never be altered
#where as work_dir can be written to and cleaned up afterwards
#is this fully supported?

#params
#-output dir should never be dataflowed! ANd is really only safe when running one analysis
#as it will send all output there
#-reload



#Make this optionally take a ResultSet and a peak analysis
#to support calling without generation of Data/FeatureSet
#if there is no feature set, we should also not load the peaks
#if we define a max peaks value, then we rename to first output to unfiltered,
#then add a filter step to the final expected output

sub fetch_input {
  my $self = shift;
  #Set some module defaults
  $self->param('disconnect_if_idle', 1);
  $self->check_analysis_can_run;
  
  $self->SUPER::fetch_input;

  my $set_type = $self->param_required('set_type');
  my ($fset, $rset, $analysis);
  
  
  #Why do we need both of these? Surely max_peaks implies filter!
  #These also needs grabbing from result_set_tracking in IdentifySetInputs
  #and dataflowing
  
  
  my $max_peaks = $self->get_param_method('max_peaks', 'silent');
  
  if($self->param_silent('filter_max_peaks') &&
     (! defined $max_peaks)){
    $self->throw_no_retry('The filter_max_peaks param has been set, but no max_peaks param has been set');
  }
  

  if($set_type eq 'ResultSet'){
    $rset = $self->fetch_Set_input('ResultSet'); 
    
    #This is likely permissive peaks for pre_IDR rep 
    
    
    #Can we not auto detect based on run_idr and is_idr_feature_type
    #No this is breaking the link between setting the analysis and the branching
    #which is based on the FeatureSet logic_name
    #This branch config is not loaded in IdentifyReplicateResultSet
    #How are we goign to do this, such that we don't risk 
    #passing the wrong analysis! i.e. It has to match the hive analysis name
    #
    
    my $peak_analysis = $self->param_required('peak_analysis');
    $analysis = scalars_to_objects($self->out_db, 'Analysis',
                                                  'fetch_by_logic_name',
                                                  [$peak_analysis])->[0];
    if(! defined $analysis){
      $self->throw_no_retry("Could not find peak_analysis in DB:\t".$peak_analysis);  
    }                            
  }
  else{
    $fset     = $self->fetch_Set_input('FeatureSet');
    $analysis = $fset->analysis;
    $rset     = $self->ResultSet; 
  }

  #This is required for getting files, move this to get_alignment_file_by_InputSets?
  $self->set_param_method( 'cell_type', $rset->cell_type, 'required' );

  #do we need both experiment name and logic name in here?
  #logic name will be in the otufile name anyway?

  $self->get_output_work_dir_methods( $self->db_output_dir . '/peaks/' .
      $rset->experiment->name. '/' . $analysis->logic_name );

  my $peak_module = validate_package_path($analysis->module);
  my $formats = $peak_module->input_formats;
  #my $filter_format = $self->param_silent('bam_filtered') ? undef : 'bam';  
  #It is currently unsafe to filter here (control clash), so expect filtered file  
  
  #The problem here is that we are returning a hash of files keys on the format
  #This conversion may cause clashes for fan job which share the same controls
  #(e.g. peak calling jobs if they require formats other than bam)
  #Collections jobs will be pre-processed/converted individually before submitting
  #the slice job.
  #So here we really only need the first available format
   
  #Restrict to bam for now
  
  if($formats->[0] ne 'bam'){
    throw("It is currently unsafe to use any non-bam format at this point.\n".
      "This is due to the possibility of filtering/format conversion clashes between parallel\n".
      "jobs which share the same control files. Please implement PreprocessAlignments to\n".
      "group jobs by controls and set/handle FILTERING_CONTROL status");  
  }
  
  $formats = ['bam'];
  my $align_file = $self->get_alignment_files_by_ResultSet_formats($rset, $formats)->{bam};
  my $control_file;  

  if ( grep {$_->is_control} @{$rset->get_support} ) {
    #This throws if not found
    $control_file = $self->get_alignment_files_by_ResultSet_formats($rset, 
                                                                    $formats, 
                                                                    1)->{bam}; # control flag
  }

  #align and control file could potentially be different formats here
  #shall we let the peak caller handle that or test here?


  #work dir is now based on the peaks and we get the input alignment file
  #above, so we don't need this dir

#my $work_dir = $self->workdir.'/'.join('/', ($self->workdir,
#                                             'alignments',
#                                             $self->species,
#                                             $self->assembly)
#                                             $experiment_name);
#workdir is currently not used!!!!
#This should be used for the samtools sort/merge stuff
#so needs defining in BaseDB?
#or just Base.pm
#Should we mirror all the subdirs from the workdir root?
#Then we can set workdir dynamically by just subing the output_dir with the work_dir

  #output_dir method should also set work_dir
  #input_dir should nevr be written to, unless it is also the output_dir

  #my $input_dir = $self->param_silent('input_dir') || $work_dir;
  #$self->set_dir_param_method('input_dir', $input_dir);

  #todo create SWEmbl runnable which does not inherit from hive
  #pass through self for access to debug/log etc?

#We must flow separately for each analysis! from the CollctionWriter preprocess job

  #This is hardcoding for packages in Bio::EnsEMBL::Funcgen::Hive
  #use full package name in analysis!

 

  #validate program_file isn't already path?

  my $pfile_path = ( defined $self->bin_dir ) ?
    $self->bin_dir.'/'.$analysis->program_file : $analysis->program_file;

  my $peak_runnable = $peak_module->new(
    -program_file      => $pfile_path,
    -parameters        => $analysis->parameters,
    -align_file        => $align_file,
    -control_file      => $control_file,
    -out_file_prefix   => $rset->name.'.'.$analysis->logic_name,
    -out_dir           => $self->output_dir,
    -convert_half_open => 1,

    #todo change this to separate flags, reload will take priority over retry?
    -is_half_open => $self->param_silent('is_half_open') || 0,    #default to closed coords
    -debug             => $self->debug,
  
  );

  #How are we going to support filtered and unfiltered feature/data_set here?
  #should we keep the peak and the alignment in the same DBagnostic
  #directory?
  #No we should at least have then in analysis_logic_name subdirs
  #and these are DB specific.

  $self->set_param_method( 'peak_runnable', $peak_runnable );

  return 1;
} ## end sub fetch_input

sub run {
  my $self = shift;

  my $out_file = $self->peak_runnable->out_file;

  if( ! ( $self->param_silent('reload') && 
          -e  $out_file) ){
       
    if(! eval { $self->peak_runnable->run; 1 }){
      my $err = $@; 
      $self->throw_no_retry('Failed to call run on '.ref($self->peak_runnable).":\n$err"); 
    }
  }

  my $max_peaks = $self->max_peaks;

  if($max_peaks){
    
    my $cmd = "mv $out_file ${out_file}.unfiltered";
    run_system_cmd($cmd);
    
    $cmd = "sort -k 7nr,7nr ${out_file}.unfiltered | head -n $max_peaks | sort -k 1,2n > ".$out_file;
    run_system_cmd($cmd);    
    #Will failures of downstream pipes be caught?   

    #Sanity check we have the file with the correct number of lines
    $cmd = "wc -l $out_file";
    my $filtered_peaks = run_backtick_cmd($cmd);
      
    if($max_peaks != $filtered_peaks){
      throw("Expected $max_peaks in filtered bed file, but found $filtered_peaks:\n\t".$out_file);  
    }       
  }

  return;
}

sub write_output {
  my $self = shift;
  
  my $fset;
  
  if($self->can('FeatureSet') &&
     ($fset = $self->FeatureSet) ){
    #test assignment, as we may have the FeatureSet method from a previous
    #job in this batch     

    if ( $fset->has_status('IMPORTED') ) {
      throw( "Cannot imported feature into a \'IMPORTED\' FeatureSet:\t" .
             $fset->name );

     #rollback should be outside of this module!
    }

    $self->peak_runnable->store_features( $self->can('store_AnnotatedFeature'),
                                          $fset,
                                          $fset->adaptor->db->get_AnnotatedFeatureAdaptor );

    $fset->adaptor->set_imported_states_by_Set($fset);

    #my $batch_params = $self->get_batch_params;

    # Log counts here?

    #No data flow to PeaksQC here as this is done via semaphore from PreprocessAlignment

    #todo update tracking states?
  }

  return;
} ## end sub write_output


sub store_AnnotatedFeature {
  my ( $self, $fset, $af_adaptor, $fhash ) = @_;

  if ( my $slice = $self->get_Slice( $fhash->{-seq_region} ) ) {
    delete ${$fhash}{-seq_region};

    eval {
      $af_adaptor->store( Bio::EnsEMBL::Funcgen::AnnotatedFeature->new(
                                 %$fhash, -slice => $slice -feature_set => $fset
                          ) );
    };

    if ($@) {
      throw( 'Could not create and store ' .
             $fset->name . " AnnotatedFeature with attributes:\n\t" .
             join( "\n\t", ( map { "$_ => " . $fhash->{$_} } keys %$fhash ) ) );
    }
  }

  # else this can only happen with -slices/skip_slices

  return;
}

1;

# Private function only to be called by subclasses of this class
# gets the number of reads in a sam or bed file
#sub _get_number_of_reads {
#   my ($self, $file, $file_type) = (shift, shift, shift);
#   if(($file_type ne "bed") && ($file_type ne "sam")){ throw "Only bed and sam file types supported"; }
#   my $nbr_reads = 0;
#   #If needed, add an option to check if is zipped or not...
#   my $open_cmd = "gzip -dc $file |";
#   open(FILE,$open_cmd);
#   while(<FILE>){
#     if($file_type eq "sam"){
#       next if /^\@SQ/;
#     }else {
#       next if /track name=/o;
#     }
#     $nbr_reads++;
#   }
#   close FILE;
#   return $nbr_reads;
#}

# Private function only to be called by subclasses of this class
# gets the number of reads in a sam or bed file
#sub _get_slices {
#  #NOT DONE!!
#   my ($self, $file, $file_type) = (shift, shift, shift);
#   if(($file_type ne "bed") && ($file_type ne "sam")){ throw "Only bed and sam file types supported"; }
#   my $nbr_reads = 0;
#   #If needed, add an option to check if is zipped or not...
#   my $open_cmd = "gzip -dc $file |";
#   open(FILE,$open_cmd);
#   while(<FILE>){
#     if($file_type eq "sam"){
#       next if /^@SQ/;
#     }else {
#       next if /track name=/o;
#     }
#     $nbr_reads++;
#   }
#   close FILE;
#   return $nbr_reads;
#}

=item input_dir 

=item skip_control

=item align_file

=item control_file

#is now injected as 'align_file'
#sub _input_file {
#  return $_[0]->_getter_setter('input_file',$_[1]);
#}

=cut

