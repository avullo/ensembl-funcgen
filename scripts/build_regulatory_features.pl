#!/software/bin/perl

=head1 NAME

build_regulatory_features.pl -- builds features for the "Ensembl 
Regulatory Build", the moral equivalent of the gene build

=head1 SYNOPSIS

build_regulatory_features.pl -host host -user user -pass password 
    -outdir output_directory -focus feature_setA,feature_setB  
    -target feature_setC,feature_setD -seq_name chr

=head1 DESCRIPTION

This script is the core to compute the regulatory features for the 
"Ensembl Regulatory Build". A regulatory feature consists of

 a) all features that directly overlap with a focus feature, and
 b) features that are contained in focus-feature-overlaping features

The following figure gives examples.

      |------|  |-------- F1 --------|   |----|

      |---------------------------------------|

  |--X--|  |------| |------|   |---------|  |--X---|

      |============= RegFeature ==============|

                                            |- F2 -|

      |=============== RegFeature =================|

[more documentation to be added]

=head1 LICENCE

This code is distributed under an Apache style licence. Please see
http://www.ensembl.org/info/about/code_licence.html for details.

=head1 AUTHOR

Stefan Graf, Ensembl Functional Genomics

=head1 CONTACT

Please post comments/questions to the Ensembl development list
<ensembl-dev@ebi.ac.uk>

=cut

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;

my ($pass,$port,$host,$user,$dbname,$species,$help,$man,
    $data_version,$outdir,$do_intersect,$write_features,$seq_name,$clobber,
    $focus,$target,$dump,$debug);
GetOptions (
            "pass|p=s"       => \$pass,
            "port=s"         => \$port,
            "host|h=s"       => \$host,
            "user|u=s"       => \$user,
            "dbname|d=s"     => \$dbname,
            "species=s"      => \$species,
            "help|?"         => \$help,
            "man|m"          => \$man,
            "data_version|v=s" => \$data_version,
            "outdir|o=s"     => \$outdir,
            "do_intersect|i=s" => \$do_intersect,
            "write_features|w" => \$write_features,
            "seq_name|s" => \$seq_name,
            "clobber" => \$clobber,
            "focus|f=s" => \$focus,
            "target|t=s" => \$target,
            "dump" => \$dump,
            "debug" => \$debug
            );

### defaults ###
$port = 3306 if !$port;
$species = 'homo_sapiens' if !$species;

### check options ###

throw("Must specify mandatory database hostname (-host).\n") if ! defined $host;
throw("Must specify mandatory database username. (-user)\n") if ! defined $user;
throw("Must specify mandatory database password (-pass).\n") if ! defined $pass;
throw("Must specify mandatory database name (-dbname).\n") if ! defined $dbname;
throw("Must specify mandatory database data version, like 47_36i (-data_version).\n") 
    if !$data_version;

throw("Must specify mandatory focus sets (-focus).\n") if ! defined $focus;
throw("Must specify mandatory target sets (-target).\n") if ! defined $target;

warn("write_features not set: do_intersect will be skipped\n") 
    if ($do_intersect && ! $write_features);

#throw("No output directory specified! Use -o option.") if (!$outdir);
if (defined $outdir && ! -d $outdir) {
    system("mkdir -p $outdir");
}
$outdir =~ s/\/$//;


$| = 1;


use Bio::EnsEMBL::Utils::Exception qw(verbose throw warning info);
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Funcgen::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Funcgen::Utils::EFGUtils qw(open_file);
use Bio::EnsEMBL::Funcgen::Utils::RegulatoryBuild qw(is_overlap);

# use ensembldb as we may want to use an old version

my $cdb = Bio::EnsEMBL::DBSQL::DBAdaptor->new
    (
     -host => 'ensembldb.ensembl.org',
     -port => 3306,
     -user => 'anonymous',
     #-host => '127.0.0.1',
     #-port => 33064,
     #-user => 'ensro',
     -dbname => $species.'_core_'.$data_version,
     -species => $species,
     );

my $db = Bio::EnsEMBL::Funcgen::DBSQL::DBAdaptor->new
    (
     -host   => $host,
     -user   => $user,
     -dbname => $dbname,
	   -species => $species,
     -pass   => $pass,
     -port   => $port,
     -dnadb  => $cdb
     );
#print Dumper $db;

my $fsa = $db->get_FeatureSetAdaptor();
#my $fta = $db->get_FeatureTypeAdaptor();
my $afa = $db->get_AnnotatedFeatureAdaptor();
my $sa = $db->get_SliceAdaptor();
#my $aa = $db->get_AnalysisAdaptor();

# parse focus and target sets and check that they exist
my (%focus_fsets, %target_fsets);
map { my $fset = $fsa->fetch_by_name($_);
      $focus_fsets{$fset->dbID} = $fset; 
      throw("Focus set $_ does not exist in the DB") 
          if (! defined $focus_fsets{$fset->dbID}); 
  } split(',', $focus);

map { 
    my $fset = $fsa->fetch_by_name($_);
    $target_fsets{$fset->dbID()} = $fset; 
      throw("Target set $_ does not exist in the DB") 
          if (! defined $target_fsets{$fset->dbID}); 
      } split(',', $target);

# make sure that target sets also contain focus sets (Do we really need this?)
map { $target_fsets{$_} = $focus_fsets{$_} } keys %focus_fsets;

# retrieve sequence to be analyzed 
my $slice;

if ($seq_name) {
  $slice = $sa->fetch_by_region('chromosome', $seq_name);
} elsif (defined $ENV{LSB_JOBINDEX}) {
  warn "Performing whole genome analysis on toplevel slices using the farm.\n";
    
  my $toplevel = $sa->fetch_all('toplevel');
  my @chr = sort (map $_->seq_region_name, @{$toplevel});
  #print Dumper @chr;
  
  my @slices;
  foreach my $chr (@chr) {
      
      next if ($chr =~ m/^NT_/);
      
      push @slices, $sa->fetch_by_region('chromosome', $chr);
  }
  #print Dumper @slices;

  $slice=$slices[$ENV{LSB_JOBINDEX}-1];      
  print Dumper ($ENV{LSB_JOBINDEX}, $slice->name);
  
} else {

    throw("Must specify mandatory chromosome name (-seq_name) or set\n ".
          "LSF environment variable LSB_JOBINDEX to perform whole\n ".
          "genome analysis on toplevel slices using the farm.\n");

}

# get core and fg seq_region_id for slice
my ($core_sr_id, $fg_sr_id);
$core_sr_id = $slice->get_seq_region_id();
#need to build cache first
$afa->build_seq_region_cache();
$fg_sr_id = $afa->get_seq_region_id_by_Slice($slice);

#should this be printing to OUT or STDERR?
#or remove as we're printing this later?
print
    '# Focus set(s): ', join(", ", map {$focus_fsets{$_}->name.' ('.$focus_fsets{$_}->dbID.')'} keys %focus_fsets), "\n",
    '# Target set(s): ', join(", ", map {$target_fsets{$_}->name.' ('.$target_fsets{$_}->dbID.')'} sort keys %target_fsets), "\n",
    '# Species: ', $species, "\n",
    '# Chromosome: ', join(" ",$slice->display_id(),$slice->get_seq_region_id), "\n",
    '#   core seq_region_id '.$core_sr_id." => fg seq_region_id ".$fg_sr_id."\n";

if ($dump) {
    
    my @fset_ids = keys %target_fsets;
    #print Dumper @fset_ids; 

    print STDERR "# Dumping annotated features from database to file.\n";
    print STDERR "# This will delete existing file dumps of that data version!\n";

    throw("Must specify directory to write the output (-outdir).\n") if ! defined $outdir;
    print STDERR "# Output goes to ", $outdir, "\n";


    my $sql = "select annotated_feature_id, seq_region_id,".
        "seq_region_start, seq_region_end,seq_region_strand,".
        "score,feature_set_id from annotated_feature";
    my $command = "echo \"$sql\" ".
        " | mysql -quick -h".$host." -P".$port." -u".$user." ".$dbname.
        " | gawk '{if (\$7==".join("||\$7==", @fset_ids).") print }'".
        " | sort -n -k 2,2 -k 3,3 -k 4,4".
        " | gawk '{ print >> \"".$outdir."/".$dbname.".annotated_feature_\" \$2 \".dat\" }'";

    print STDERR "# Execute: ".$command."\n" if ($debug);
    
    # need to remove existing dump files, since we append to the file
    system("rm -f $outdir/$dbname.annotated_feature_*.dat") &&
        throw ("Can't remove files");

    system($command) &&
        throw ("Can't dump data to file in $outdir");

    exit;

}

my $fh = open_file($outdir.'/'.$dbname.'.annotated_feature_'.$fg_sr_id.'.dat');

# Read from file and process sequentially in sorted by start, end order. Each 
# new feature is checked if it overlaps with the preceeding already seen 
# features. If yes we just carry on with the next one. Otherwise


my (@features, $focus_end, @regulatory_features, %regulatory_feature);
my ($af_id, $sr_id, $start, $end, $strand, $score, $fset_id);

while (<$fh>) {

	next if (/^#/);
	
	print if ($debug);

    ($af_id, $sr_id, $start, $end, $strand, $score, $fset_id) = split (/\s+/, $_);
    #print Dumper ($af_id, $sr_id, $start, $end, $strand, $score, $fset_id);
	#print $af_id, "\n";

	if (exists $focus_fsets{$fset_id}) {


		# current feature is focus feature
		print "focus feature ($af_id)\n" if ($debug);

		# no regulatory feature seed available
		if ( ! %regulatory_feature ) {

			%regulatory_feature = (
				'start' => $start,
				'end' => $end,
				'annotated' => { 
					$af_id => undef 
				});
			
			$focus_end = $regulatory_feature{end};

			&update_5prime();

		} else {

			
			if ($start < $regulatory_feature{end}) {
			
				print "focus_feature overlaps regulatory feature; add ($af_id) to reg. feature\n"
					if ($debug);
	
				# add annot. feature id to reg. feature
				$regulatory_feature{annotated}{$af_id} = undef;

				# update end of regulatory feature
				$regulatory_feature{end} = $end
					if ($end > $regulatory_feature{end});

				# add annot. feature id to reg. feature
				map {
					if ($_->{end} <= $regulatory_feature{end}) {
						print "add (".$_->{af_id}.") to reg. feature\n" if ($debug);
						$regulatory_feature{annotated}{$_->{af_id}} = undef 
					} 
				} @features;

				@features = ();
					
			} else {

				print "close regulatory feature\n" if ($debug);
				push(@regulatory_features, %regulatory_feature);

				%regulatory_feature = (
					'start' => $start,
					'end' => $end,
					'annotated' => { 
						$af_id => undef 
					});
			
				$focus_end = $regulatory_feature{end};

				&update_5prime();

			}

		}

		$focus_end = ($end > $focus_end) ? $end : $focus_end;

	} else {

		# ordinary feature

		if ( defined $focus_end && $start <= $focus_end ) {

			print "overlap w/ focus feature; add (".$af_id.") to reg. feature\n" 
				if ($debug);

			# add annot. feature id to reg. feature
			$regulatory_feature{annotated}{$af_id} = undef;
			
			# update end of regulatory feature
			$regulatory_feature{end} = $end
				if ($end > $regulatory_feature{end});
			
		} elsif (%regulatory_feature && $end <= $regulatory_feature{end}) {

			print "contained within reg. feature; add ($af_id) to reg. feature\n" 
				if ($debug);

			# add annot. feature id to reg. feature
			$regulatory_feature{annotated}{$af_id} = undef;
			
		} else {

			print "add to feature list ($af_id)\n" if ($debug);
			&add_feature();

		}

	}
			
}

if (%regulatory_feature) {
	push(@regulatory_features, %regulatory_feature);

}

print "\n", Dumper @regulatory_features;


sub add_feature ()
{

    push(@features, 
         {
             af_id => $af_id,
             start => $start,
             end => $end,
             strand => $strand,
             score => $score,
             fset_id => $fset_id
             }
         );

}

sub update_5prime()
{
	
	# look upstream for features overlaping with focus feature
	
	foreach my $ft (@features) {
		
		if ($ft->{end} >= $start) {
			
			print "1st feature that overlaps w/ focus (".$ft->{af_id}.")\n" if ($debug);
			
			# update start of regulatory feature
			$regulatory_feature{start} = $ft->{start}
			if ($ft->{start} < $regulatory_feature{start});
			
			# add all annot. features (af_ids) from the list to reg. feature 
			# and update reg. feature end if necessary
			map {
				if ($_->{start} >= $regulatory_feature{start})
				{
					print "add (".$_->{af_id}.") to reg. feature\n" if ($debug);
					$regulatory_feature{annotated}{$_->{af_id}} = ();
					$regulatory_feature{end} = $_->{end}
								if ($_->{end} > $regulatory_feature{end});
				}
			} @features;
			
			print "empty feature list\n" if ($debug);
			@features = ();
			
			last;
			
		}
		
	}

}



1;
