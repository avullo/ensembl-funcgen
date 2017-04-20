=head1 LICENSE

Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=head1 NAME

  Bio::EnsEMBL::Funcgen::ProbeSetTranscriptMapping

=head1 SYNOPSIS
=head1 DESCRIPTION
=cut

package Bio::EnsEMBL::Funcgen::ProbeSetTranscriptMapping;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument  qw( rearrange );
use Bio::EnsEMBL::Utils::Exception qw( throw deprecate );

sub new {
  my $caller = shift;
  my $class = ref($caller) || $caller;
  my $self = bless {}, $class;

  my @field = qw(
    dbID
    probeset_id
    stable_id
    description
    adaptor
  );
  
  my (
    $dbID,
    $probeset_id,
    $stable_id,
    $description,
    $adaptor
  )
    = rearrange([ @field ], @_);

  $self->dbID            ($dbID);
  $self->stable_id       ($stable_id);
  $self->description     ($description);
  $self->probeset_id        ($probeset_id);
  $self->adaptor         ($adaptor);

  return $self;
}

sub dbID           { return shift->_generic_get_or_set('dbID',            @_) }
sub adaptor        { return shift->_generic_get_or_set('adaptor',         @_) }
sub stable_id      { return shift->_generic_get_or_set('stable_id',       @_) }
sub description    { return shift->_generic_get_or_set('description',     @_) }
sub probeset_id    { return shift->_generic_get_or_set('probeset_id',     @_) }

sub display_id {
  my $self = shift;
  deprecate(
    "display_id has been deprecated and will be removed in Ensembl release 92."
        . " Please use stable_id instead."
  );
  return $self->stable_id
}

sub linkage_annotation {
  my $self = shift;
  deprecate(
    "linkage_annotation has been deprecated and will be removed in Ensembl release 92."
        . " Please use description instead."
  );
  return $self->description;
}

sub fetch_ProbeSet {
  my $self = shift;
  my $probeset = $self->adaptor->get_ProbeSetAdaptor->fetch_by_dbID($self->probeset_id);
  return $probeset;
}

sub _generic_get_or_set {
  my $self  = shift;
  my $name  = shift;
  my $value = shift;

  if(defined $value) {
    $self->{$name}  = $value;
  }
  return $self->{$name};
}

1;


