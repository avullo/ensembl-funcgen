#
# Ensembl module for Bio::EnsEMBL::Funcgen::DBSQL::CellTypeAdaptor
#
# You may distribute this module under the same terms as Perl itself

=head1 NAME

Bio::EnsEMBL::Funcgen::DBSQL::CellTypeAdaptor - A database adaptor for fetching and
storing Funcgen CellType objects.

=head1 SYNOPSIS

my $ct_adaptor = $efgdba->get_CellTypeAdaptor();

my $cell_type = $ct_adaptor->fetch_by_name("HeLa");


=head1 DESCRIPTION

The CellTypeAdaptor is a database adaptor for storing and retrieving
Funcgen CellType objects.

=head1 AUTHOR

This module was created by Nathan Johnson.

This module is part of the Ensembl project: http://www.ensembl.org/

=head1 CONTACT

Post comments or questions to the Ensembl development list: ensembl-dev@ebi.ac.uk

=head1 METHODS

=cut

use strict;
use warnings;

package Bio::EnsEMBL::Funcgen::DBSQL::CellTypeAdaptor;

use Bio::EnsEMBL::Utils::Exception qw( warning throw );
use Bio::EnsEMBL::Funcgen::CellType;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;

use vars qw(@ISA);


#May need to our this?
@ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);

=head2 fetch_by_name

  Arg [1]    : string - name of CellType
  Arg [1]    : optional string - class of CellType
  Example    : my $ct = $ct_adaptor->fetch_by_name('HeLa');
  Description: Retrieves CellType objects by name.
  Returntype : Bio::EnsEMBL::Funcgen::CellType object
  Exceptions : Throws no name given
  Caller     : General
  Status     : At risk

=cut

sub fetch_by_name{
  my ($self, $name) = @_;

  throw("Must specify a CellType name") if(! $name);

  my $constraint = "ct.name ='$name'";

  my @ctype = @{$self->generic_fetch($constraint)};
  #name is unique so we should only have one

  return $ctype[0];
}




=head2 _tables

  Args       : None
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Returns the names and aliases of the tables to use for queries.
  Returntype : List of listrefs of strings
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _tables {
  my $self = shift;
	
  return (
	  ['cell_type', 'ct'],
	 );
}

=head2 _columns

  Args       : None
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Returns a list of columns to use for queries.
  Returntype : List of strings
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _columns {
  my $self = shift;
	
  return qw( ct.cell_type_id ct.name ct.display_label ct.description ct.gender);#ct.type/class
}

=head2 _objs_from_sth

  Arg [1]    : DBI statement handle object
  Example    : None
  Description: PROTECTED implementation of superclass abstract method.
               Creates Channel objects from an executed DBI statement
			   handle.
  Returntype : Listref of Bio::EnsEMBL::Funcgen::CellType objects
  Exceptions : None
  Caller     : Internal
  Status     : At Risk

=cut

sub _objs_from_sth {
	my ($self, $sth) = @_;
	
	my (@result, $ct_id, $name, $dlabel, $desc, $gender);
	
	$sth->bind_columns(\$ct_id, \$name, \$dlabel, \$desc, \$gender);
	
	while ( $sth->fetch() ) {
		my $ctype = Bio::EnsEMBL::Funcgen::CellType->new(
														 -dbID          => $ct_id,
														 -NAME          => $name,
														 -DISPLAY_LABEL => $dlabel,
														 -DESCRIPTION   => $desc,
														 -GENDER        => $gender,
														 -ADAPTOR       => $self,
														);
	  
		push @result, $ctype;
	  
	}
	return \@result;
}



=head2 store

  Args       : List of Bio::EnsEMBL::Funcgen::CellType objects
  Example    : $chan_a->store($c1, $c2, $c3);
  Description: Stores CellType objects in the database.
  Returntype : None
  Exceptions : None
  Caller     : General
  Status     : At Risk

=cut

sub store {
  my $self = shift;
  my @args = @_;
  
  
  my $sth = $self->prepare("
			INSERT INTO cell_type
			(name, display_label, description, gender)
			VALUES (?, ?, ?, ?)");
    
  
  
  foreach my $ct (@args) {
	  if ( ! $ct->isa('Bio::EnsEMBL::Funcgen::CellType') ) {
		  warning('Can only store CellType objects, skipping $ct');
		  next;
	  }
	  
	  if ( $ct->dbID() && $ct->adaptor() == $self ){
		  warn("Skipping previously stored CellType dbID:".$ct->dbID().")");
		  next;
	  }
	  
	  
	  $sth->bind_param(1, $ct->name(),           SQL_VARCHAR);
	  $sth->bind_param(2, $ct->display_label(),  SQL_VARCHAR);
	  $sth->bind_param(3, $ct->description(),    SQL_VARCHAR);
	  $sth->bind_param(4, $ct->gender(),         SQL_VARCHAR);
	  
	  
	  $sth->execute();
	  $ct->dbID($sth->{'mysql_insertid'});
	  $ct->adaptor($self);
	  
  }

  return \@args;
}


=head2 list_dbIDs

  Args       : None
  Example    : my @ct_ids = @{$ct_a->list_dbIDs()};
  Description: Gets an array of internal IDs for all CellType objects in the
               current database.
  Returntype : List of ints
  Exceptions : None
  Caller     : ?
  Status     : At risk

=cut

sub list_dbIDs {
    my ($self) = @_;
	
    return $self->_list_dbIDs('cell_type');
}



1;

