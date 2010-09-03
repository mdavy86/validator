package ModENCODE::Validator::ReadCounts;
use strict;
use Class::Std;
use ModENCODE::Parser::Chado;
use ModENCODE::ErrorHandler qw(log_error);

my %experiment                  :ATTR( :init_arg<experiment>,           :get<experiment> );

sub validate {
  my ($self) = @_;
  my $experiment = $self->get_experiment();
  my @properties = $experiment->get_properties(1);
  my ($uniq_reads) = grep { $_->get_type(1)->get_name eq "uniquely_mapped_read_count" } @properties;
  my ($multiply_mapped_reads) = grep { $_->get_type(1)->get_name eq "multiply_mapped_read_count" } @properties;
  my ($total_reads) = grep { $_->get_type(1)->get_name eq "read_count" } @properties;

  if ($uniq_reads || $multiply_mapped_reads || $total_reads) {
    if ($uniq_reads) {
      $uniq_reads = $uniq_reads->get_value();
      log_error "Found $uniq_reads uniquely mapped reads.", "notice";
    }
    if ($multiply_mapped_reads) {
      $multiply_mapped_reads = $multiply_mapped_reads->get_value();
      log_error "Found $multiply_mapped_reads multiply mapped reads.", "notice";
    }
    if ($total_reads) {
      $total_reads = $total_reads->get_value();
      log_error "Found $total_reads total reads.", "notice";
    }
    if (!$total_reads) {
      # First make sure we have as many of these as we can from somewhere (e.g. reffed experiments)
      # Look for referenced submissions
      my %referenced_submissions; 
      foreach my $applied_protocol_slot (@{$experiment->get_applied_protocol_slots}) { 
        foreach my $applied_protocol (@$applied_protocol_slot) { 
          foreach my $datum ($applied_protocol->get_input_data(1), $applied_protocol->get_output_data(1)) {
            my ($reference) = grep { $_->get_termsource() && $_->get_termsource(1)->get_db(1)->get_description eq "modencode_submission" } $datum->get_attributes(1);
            if ($reference) {
              $referenced_submissions{$reference->get_termsource(1)->get_db(1)->get_url()} = 1;
            }
          }
        } 
      }

      my $parser = $self->get_modencode_chado_parser();
      foreach my $referenced_submission_id (keys(%referenced_submissions)) {
        $parser->set_schema("modencode_experiment_" . $referenced_submission_id . "_data");
        my $others;
#        if (!$uniq_reads) {
#          ($uniq_reads, $others) = $parser->get_experiment_props_by_type_name('uniquely_mapped_read_count');
#          if ($others) { log_error "Got back more than one unique read count from referenced submission $referenced_submission_id.", "warning"; }
#          if ($uniq_reads) {
#            $uniq_reads = $uniq_reads->get_object->get_value();
#            log_error "Found (missing from this submission) $uniq_reads uniquely mapped reads in submission $referenced_submission_id.", "notice";
#          }
#        }
#        if (!$multiply_mapped_reads) {
#          ($multiply_mapped_reads, $others) = $parser->get_experiment_props_by_type_name('multiply_mapped_read_count');
#          if ($others) { log_error "Got back more than one multiply mapped read count from referenced submission $referenced_submission_id.", "warning"; }
#          if ($multiply_mapped_reads) {
#            $multiply_mapped_reads = $multiply_mapped_reads->get_object->get_value();
#            log_error "Found (missing from this submission) $multiply_mapped_reads multiply mapped reads in submission $referenced_submission_id.", "notice";
#          }
#        }
        if (!$total_reads) {
          ($total_reads, $others) = $parser->get_experiment_props_by_type_name('read_count');
          if ($others) { log_error "Got back more than one total read count from referenced submission $referenced_submission_id.", "warning"; }
          if ($total_reads) {
            $total_reads = $total_reads->get_object->get_value();
            log_error "Found (missing from this submission) $total_reads total reads in submission $referenced_submission_id.", "notice";
          }
        }
      }
    }

    my $mapped_reads = $uniq_reads + $multiply_mapped_reads;
    my $read_ratio = ($mapped_reads / $total_reads) * 100;
    if ($read_ratio <= 30) {
      log_error "Only " . int($read_ratio) . "% of reads were mapped; your data set must map at least 30%!", "error";
      return 0;
    } else {
      log_error int($read_ratio) . "% of reads were mapped (more than 30%).", "notice";
      return 1;
    }
  }

  return 1;
}

sub get_modencode_chado_parser : PROTECTED {
  my ($self) = @_;
  my $parser = new ModENCODE::Parser::Chado({
      'dbname' => ModENCODE::Config::get_cfg()->val('databases modencode', 'dbname'),
      'host' => ModENCODE::Config::get_cfg()->val('databases modencode', 'host'),
      'port' => ModENCODE::Config::get_cfg()->val('databases modencode', 'port'),
      'username' => ModENCODE::Config::get_cfg()->val('databases modencode', 'username'),
      'password' => ModENCODE::Config::get_cfg()->val('databases modencode', 'password'),
      'caching' => 0,
    });
  return undef unless $parser;
  $parser->set_no_relationships(1);
  $parser->set_child_relationships(1);
  return $parser;
}


1;
