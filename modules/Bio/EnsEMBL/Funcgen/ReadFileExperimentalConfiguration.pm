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

sub _constructor_parameters {
  return {
    technical_replicate  => 'technical_replicate',
    biological_replicate => 'biological_replicate',
    paired_end_tag       => 'paired_end_tag',
    multiple             => 'multiple',
    read_file_id         => 'read_file_id',
    experiment_id        => 'experiment_id',
  }
}

sub _simple_accessors {
  return [
    { method_name => 'biological_replicate', hash_key => '_biological_replicate', },
    { method_name => 'technical_replicate',  hash_key => '_technical_replicate',  },
    { method_name => 'paired_end_tag',       hash_key => '_paired_end_tag',       },
    { method_name => 'multiple',             hash_key => '_multiple',             },
    { method_name => 'read_file_id',         hash_key => '_read_file_id',         },
    { method_name => 'experiment_id',        hash_key => '_experiment_id',        },
  ]
}

sub fetch_ReadFile {

  my $self = shift;
  
  my $read_file_id = $self->read_file_id;
  my $read_file    = $self->db->db->get_ReadFileAdaptor
    ->fetch_by_dbID($read_file_id);

  return $read_file;
}

1;





