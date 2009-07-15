#!/software/bin/perl


=head1 NAME

load_bed_source.pl

=head1 SYNOPSIS

load_bed_source.pl --files file1 file2 file3 [ --names source_name1 source_name2 source_name3 --prefix source_name_prefix ]





=head1 DESCRIPTION

This script loads a DAS source from raw read alignments(bed) and/or 
profiles generated from them.

=head1 LICENSE

  Copyright (c) 1999-2009 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

    http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <ensembl-dev@ebi.ac.uk>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.


=cut

#To do
#Integrate this with the collection code to get a set of bins
#Merge this with load_bed, or load directly?
#No need to keep reads/profile file? Can always dump out from DB?
#Remove/implement multiple files properly, current overwrites previous table load
#Change reads/profile support to be explicit options
#Implement multiple windows sizes? Or matrix? MySQL COMPRESS?
#Change to use mysqlimport


use strict;
use warnings;
use Pod::Usage;
use Getopt::Long;
use DBI;

my ($pass,$port,$host,$user,$dbname,$prefix, $file, @files, @names);
my ($no_load, $bin_size, $frag_length, $skip_profile, @formats, $name);
my ($profile, $reads);

my $params_msg = "Params are:\t@ARGV";

GetOptions (
            'host|h=s'         => \$host,
            'port:i'           => \$port,
            'user|u=s'         => \$user,
            'pass|p:s'         => \$pass,
            'dbname|d=s'       => \$dbname,
			'files=s{,}'       => \@files,
			'reads'            => \$reads,
			'profile'          => \$profile,
			'skip_profile'     => \$skip_profile,
			'prefix=s'         => \$prefix,
			'names=s{,}'       => \@names,
			'bin_size=i'       => \$bin_size,
			'no_load'          => \$no_load,
            'frag_length=i'    => \$frag_length,
            'help|?'           => sub { pos2usage(-exitval => 0, -message => $params_msg);},
            'man|m'            => sub { pos2usage(-exitval => 0, -message => $params_msg, verbose => 2);},
		   ) or pod2usage ( -exitval => 1,
							-message => $params_msg
						  );



if (@ARGV){
  pod2usage( -exitval =>1,
			 -message => "You have specified incomplete options. $params_msg");
}


#Check params

if( ! ($host && $user && $pass && $dbname)){
  die("You must provide some DB connection paramters:\t --host --user --pass --dbname [ --port ]");
}

if(! ($reads || $profile)){
  die('Must provide at least one format to process e.g. --reads or --profile');
}
elsif($no_load && ! $profile){
  die('You have selected options --no_load without specifying --profile, no action taken');
}
elsif($profile &&
	  ! ($bin_size && $frag_length)){
  die('You must provide a --bin_size and a --frag_length to generate a profile');
}
elsif(($bin_size || $frag_length) &&
	  (! $profile)){
  die('You have specified a --bin_size and/or --frag_length, did you want to load a --profile?')
}

if(@names &&
   scalar(@names) != scalar(@files)){
  die('You have specified an unmatched number of source names, these must match the number and order of your -files');
}

#Get/Check file
if (exists $ENV{LSB_JOBINDEX}) {
  @files = ($files[$ENV{LSB_JOBINDEX}-1]);
  @names = ($names[$ENV{LSB_JOBINDEX}-1]);
}
else{

  if(scalar(@files) > 1){
	throw('You have specified more than one file, maybe you want to submit this to the farm using run_build_profile.sh|LoadBedDASSources');
  }

  @files = ($files[0]);
  @names = ($names[0]);
}

$file = $files[0];
$name = $names[0];



if(! -f $file){
  throw("File does not exist:\t$file\nMust provide at least one file path to build a profile");
}

my (@bin, $start_bin, $start_bin_start, $end_bin, $end_bin_start,
	$seq, $read_start, $read_end, $read_length, $ori, $read_extend);

if($profile && ! $skip_profile){


  #Build profile
  print ":: Building profile for:\t$file\n";

  
  open(CMD, "file -L $file |")
	or die "Can't execute command: $!";
  my $gzip = grep {/gzip compressed data/} (<CMD>);
  close CMD;

  if($gzip){
	open(FILE, "gzip -dc $file |") or die ("Can't open compressed file:\t$file");
  }
  else{
	open(FILE, $file) or die ("Cannot open file:$file");
  }


  my $binsize = sprintf("%03d", $bin_size);
  (my $out = $file) =~ s,_reads\.bed,_profile_${binsize}.bed,;

  open(OUT, "| gzip -c > $out")
    or throw ("Can't open out file $out");

  while (<FILE>) {
    chomp;
    my @col = split("\t");
  
    if (defined $seq && $seq ne $col[0]) {
	  &write_bins();
	  @bin = ();
	}

    $seq = $col[0];
    $read_start = $col[1];
    $read_end = $col[2];
    $read_length = $read_end-$read_start+1;
    $ori = $col[5];

    die("read is longer ($read_length) than specified fragment length ($frag_length)") if ($frag_length<$read_length);

    $read_extend = $frag_length-$read_length;
	
	# extend reads to given fragment length
	if ($ori eq '+') {
	  $read_end+=$read_extend;
    } else {
	  $read_start-=$read_extend;
        $read_start=1 if ( $read_start < 1 );
    }

    # update read length
    $read_length = $read_end-$read_start+1;
    
    # determine bins that are covered by the read and add 
    # coverage to bin score
	$start_bin = sprintf("%d", ($read_start-1)/$bin_size);
    #start pos of start bin
    $start_bin_start = ($start_bin*$bin_size)+1;

    $end_bin = sprintf("%d", ($read_end-1)/$bin_size);
    #start pos of end bin
    $end_bin_start = ($end_bin*$bin_size)+1;

    #printf "%s\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%d\n", 
    #$seq, $read_start, $read_end, $read_length,	$ori,
    #$start_bin, $start_bin_start, 
    #$end_bin, $end_bin_start;

    if ($start_bin == $end_bin) { ## read start and end together in one bin
	  $bin[$start_bin] += $read_length/$bin_size;
	} 
	else {
	  $bin[$start_bin] += (($start_bin_start+$bin_size)-$read_start)/$bin_size;
        #print "(($start_bin_start+$bin_size)-$read_start)/$bin_size = "
        #    .(($start_bin_start+$bin_size)-$read_start)/$bin_size."\n";
        
        for (my $i=$start_bin+1; $i<$end_bin; $i++) {

            #print $i, "\n";
            $bin[$i]++;

        }

        $bin[$end_bin] += ($read_end-$end_bin_start+1)/$bin_size;
        #print "($read_end-$end_bin_start+1)/$bin_size = "
        #    .($read_end-$end_bin_start+1)/$bin_size."\n";
	  
    }

  }

  &write_bins;

  close FILE;
  close OUT;

  push @files, $out;

}


if( ! $no_load){

  warn("No Hydra source name prefix specified!\n") if (! $prefix);

  my $dbh = DBI->connect("DBI:mysql:database=$dbname;host=$host;port=$port",
						 "$user", "$pass",
						 {'RaiseError' => 1});




  my $format;

  #Validate/identify file type, not by name!
  foreach my $i(0..$#files){

	if( ($#files == 0 && $reads) ||
		($#files == 1 && $i == 0)){
		  $format = 'reads';
		}
	elsif( ($#files == 0 && $profile) ||
		   ($#files == 1 && $i == 1)){
	  $format = 'profile';
	}
	else{
	  die('Not catching load file type correctly');
	}
  
	$file = $files[$i];
	
	print ":: Loading $format file:\t$file\n";
	open(CMD, "file -L $file |")
	  or die "Can't execute command: $!";
	my $gzip = grep {/gzip compressed data/} (<CMD>);
	close CMD;

	my $link;
	$link = 1 if -l $file;
	
	if ($gzip) {
	  print ":: Decompressing $file\n";

	  #Get the suffix?

	  #Backup link
	  if($link){
		system("cp -fP $file ${file}.backup") or die('Failed to backup link');
	  }
	  

	  system("gzip -df $file") == 0
        or die "Can't decompress file $file";
	  $file =~ s/\.gz$//;
	  die("$file does not exit, expected suffix is .gz") if (! -f $file);
	}
	
	#Can we split this into something more readable/useable
	#We need to be able to identify these table in an funcgen schema
	#Stanard prefix
	#bed_reads|profile_PREFIX_NAME

	#Maximal match/remove path and bed suffix
	
	if(! $name){
	  ($name=$file) =~ s,^(.*/)?(.+)\.bed$,$2,;
	  #remove .'s for MySQL
	  $name =~ s,\.,_,g;
	}

	$name = $prefix.'_'.$name if($prefix);
	$name = 'bed_'.$format.'_'.$name;

	if(length($name) >64){
	  die("Table name exceeded MySQL maximum of 64 characters:\t$name\n".
		  'Please rename your file or choose a shorter --prefix or --names to rectify');
	}

	print ':: Table name: ', $name, "\n";

	my $sth = $dbh->do("DROP TABLE IF EXISTS `$name`;");
		
	$sth = $dbh->do("CREATE TABLE `$name` (
    `feature_id`    INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
    `seq_region`    VARCHAR(20) NOT NULL,
    `start`         INT(10) UNSIGNED NOT NULL DEFAULT '0',
    `end`           INT(10) UNSIGNED NOT NULL DEFAULT '0',
    `name`          VARCHAR(40) NOT NULL,
    `score`         FLOAT NOT NULL DEFAULT '0',
    `strand`        ENUM('0','+','-') DEFAULT '0',
    `note`          VARCHAR(40) DEFAULT NULL,
    PRIMARY KEY     (`feature_id`),
    KEY `seq_region_idx` (`seq_region`, `start`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COLLATE=latin1_bin;");

	
	#This needs to change to mysqlimport!!!

	if ($format eq 'reads') {
	  
	  $sth = $dbh->do("LOAD DATA LOCAL INFILE '$file' INTO TABLE $name 
               (seq_region,start,end,name,\@mm,strand,score) 
               set seq_region=replace(seq_region, 'chr', ''), note=concat('mm=',\@mm);");
  
	} 
	elsif ($format eq 'profile') {
	  
	  $sth = $dbh->do("LOAD DATA LOCAL INFILE '$file' INTO TABLE $name 
               (seq_region,start,end,name,score,strand) 
               set seq_region=replace(seq_region, 'chr', '');");
	  
	}

	$dbh->disconnect();

	print ":: Finished loading $file\n";

	if ($gzip) {
	  
	  #We need to remove if the file and regenrate link if file was link?
	  
	  if($link){
		print ":: Restoring link\n";
		system("cp -f ${file}.gz.backup ${file}.gz") or die('Failed to restore link');
	  }
	  else{
		print ":: Compressing file $file...\n";
		system("gzip $file") == 0
		  or die "Can't compress file $file: $!";
	  }	
	}
  }
}




sub write_bins () {

    my ($bin_start, $bin_end);

    for (my $i=0; $i<=$#bin; $i++) {

        $bin_start = $i*$bin_size+1;
        $bin_end = $bin_start+$bin_size-1;
        
        if (defined $bin[$i]) {
            printf OUT "%s\t%d\t%d\t.\t%.1f\n", 
            $seq, $bin_start, $bin_end, $bin[$i];
        }

    }

    return 1;

}

1;
