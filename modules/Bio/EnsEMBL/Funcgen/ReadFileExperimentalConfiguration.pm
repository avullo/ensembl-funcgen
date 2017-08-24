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

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

package Bio::EnsEMBL::Funcgen::ReadFileExperimentalConfiguration;

use strict;
use warnings;

use base 'Bio::EnsEMBL::Funcgen::GenericGetSetFunctionality';

sub _simple_accessor_fields {
  return qw(
    technical_replicate
    biological_replicate
  );
}

sub _setter_fields {
  return qw(
    read_file
    experiment
  );
}

sub biological_replicate { return shift->_generic_get_or_set('biological_replicate', @_) }
sub technical_replicate  { return shift->_generic_get_or_set('technical_replicate',  @_) }

sub set_Experiment       { return shift->_generic_set('Experiment',  'Bio::EnsEMBL::Funcgen::Experiment', @_) }
sub get_Experiment       { return shift->_generic_get('Experiment',  @_) }

sub set_ReadFile { return shift->_generic_set('ReadFile',  'Bio::EnsEMBL::Funcgen::ReadFile', @_) }
sub get_ReadFile { return shift->_generic_get('ReadFile',  @_) }

1;
